import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../services/audio/cue_player.dart';
import '../../services/audio/keyword_tokens.dart' as tokens;
import '../../services/audio/mic_keep_alive.dart';
import '../../services/audio/tts_player.dart';
import '../../services/audio/wake_model_installer.dart';
import '../../services/gemini_service.dart';
import '../../services/hermes_sync_service.dart';
import '../../services/hermes_websocket_client.dart';
import '../../services/hub_tts_service.dart';
import '../../services/night_dimmer.dart';
import '../../services/photo_manifest_service.dart';
import '../../services/protocol/hermes_message.dart';
import '../../services/screen/screen_control.dart';
import '../../services/sen_memory_service.dart';
import '../../services/sen_pack_service.dart';
import '../../services/settings_service.dart';
import '../../services/update/app_platform.dart';
import '../../services/update/app_updater.dart';
import '../../services/wake_word_service.dart';
import '../constants/app_constants.dart';
import '../media/rich_content.dart';
import '../media/spoken_summary.dart';
import '../members/member_profile.dart';
import '../pack/sen_pack_registry.dart';
import '../photos/photo_context.dart';
import '../photos/photo_frame.dart';
import '../skills/sen_skill.dart';
import '../skills/skill_content.dart';
import 'brain_mode.dart';
import 'connection_status.dart';
import 'display_state.dart';

enum SendResult { sent, empty, offline }

enum ListenResult { started, busy, offline, noPermission, micUnavailable }

/// Single source of truth for the display. UI reads from here and calls
/// intents; services are never touched by widgets directly.
class DisplayController extends ChangeNotifier {
  DisplayController({
    required SettingsService settingsService,
    required HermesWebSocketClient client,
    WakeWordService? voice,
    MicKeepAlive? keepAlive,
    WakeModelInstaller? installer,
    ScreenControl? screen,
    NightDimmer? dimmer,
    TtsPlayer? tts,
    GeminiService? gemini,
    HermesSyncService? sync,
    HubTtsService? hubTts,
    SenMemoryService? memory,
    SenPackService? pack,
    AppUpdater? updater,
    PhotoFrame? photos,
  }) : _settingsService = settingsService,
       _client = client,
       _voice = voice,
       _keepAlive = keepAlive,
       _installer = installer,
       _screen = screen,
       _dimmer = dimmer,
       _tts = tts,
       _gemini = gemini,
       _sync = sync,
       _hubTts = hubTts,
       _memory = memory,
       _pack = pack,
       _updater = updater,
       _photos = photos ?? PhotoFrame(),
       _settings = settingsService.load();

  final SettingsService _settingsService;
  final HermesWebSocketClient _client;

  /// Null on builds without a microphone pipeline; mic button then only
  /// signals the hub.
  final WakeWordService? _voice;

  /// Null: no foreground service; the mic pauses with the app.
  final MicKeepAlive? _keepAlive;

  /// Null: no download; the model must already be on disk.
  final WakeModelInstaller? _installer;

  /// Null: wake word never lights the screen or shows over the lock.
  final ScreenControl? _screen;

  /// Null: no night dimming.
  final NightDimmer? _dimmer;

  /// Null: replies are shown, never spoken.
  final TtsPlayer? _tts;

  /// Null: every turn goes to the hub.
  final GeminiService? _gemini;

  /// Null: "Save to Hermes" always fails.
  final HermesSyncService? _sync;

  /// Null: Gemini answers are shown, never spoken.
  final HubTtsService? _hubTts;

  /// Null: Gemini gets no member memory and skill scores are not kept.
  final SenMemoryService? _memory;

  /// Null: built-in family and skills only.
  final SenPackService? _pack;

  /// Null: no APK over-the-air updates.
  final AppUpdater? _updater;
  static final ValueNotifier<UpdateState> _noUpdate =
      ValueNotifier<UpdateState>(UpdateState.idle);
  Timer? _packTimer;
  Future<PackSyncResult>? _packRun;
  AppLifecycleListener? _lifecycle;
  final SenPackRegistry _registry = SenPackRegistry();

  /// Slideshow state; Gemini sees the photo on screen when asked.
  final PhotoFrame _photos;
  static final ValueNotifier<bool> _neverDimmed = ValueNotifier<bool>(false);
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final ValueNotifier<double> _level = ValueNotifier<double>(0);
  Timer? _watchdog;

  HubSettings _settings;
  DisplayState _state = DisplayState.idle;
  ConnectionStatus _connection = ConnectionStatus.disconnected;
  String _transcript = '';
  String _reply = '';
  String? _lastError;
  RichContent? _rich;

  /// Last skill card; survives turns so a quiz can be answered by voice
  /// and a roleplay continues. Cleared by plain replies and dismiss.
  RichContent? _session;
  int? _quizPick;
  static const String _contextGap = '\n\n';

  /// Bumped per Gemini turn and on cancel so late answers are dropped.
  int _geminiTurn = 0;

  /// Owner of the current turn; a hub drop only ends hub turns.
  BrainMode _turnBrain = BrainMode.hub;

  /// PCM of the current capture, sent to Gemini when the hub is offline.
  final BytesBuilder _capturePcm = BytesBuilder(copy: false);
  static const String _ttsOffline = 'Hub offline: Gemini answer shown only';
  static const String _ttsFailed = 'Hub TTS unavailable: answer shown only';
  static const String _ttsPlayFailed = 'TTS playback failed';
  VoiceStatus? _voiceStatus;
  bool _starting = false;
  bool _screenWoken = false;
  ScreenResult? _screenResult;
  bool _disposed = false;

  HubSettings get settings => _settings;
  DisplayState get state => _state;
  ConnectionStatus get connection => _connection;
  String get transcript => _transcript;
  String get reply => _reply;
  String? get lastError => _lastError;

  /// Video/steps card for the last reply; stays after the turn ends.
  RichContent? get rich => _rich;

  /// Chosen option of the shown quiz, null until answered.
  int? get quizPick => _quizPick;

  MemberProfile get member => _registry.byId(_settings.activeMemberId);

  /// Family shown in the switcher: the knowledge pack's, else built-in.
  List<MemberProfile> get members => _registry.members;
  VoiceStatus? get voiceStatus => _voiceStatus;

  PhotoFrame get photos => _photos;

  /// Outcome of the last lock-screen wake/release call.
  ScreenResult? get screenResult => _screenResult;

  /// APK update progress; ready means the badge offers to install.
  ValueListenable<UpdateState> get update => _updater?.state ?? _noUpdate;

  /// True inside the night window while no turn or touch holds brightness.
  ValueListenable<bool> get nightDimmed => _dimmer?.dimmed ?? _neverDimmed;

  /// Any touch on the display: full brightness for a short while, and
  /// silences a reply being spoken.
  void touch() {
    _dimmer?.touch();
    _stopSpeech();
  }

  bool get _speaking => _tts?.isPlaying ?? false;

  InstallProgress get modelProgress {
    return _installer?.progress.value ?? InstallProgress.idle;
  }

  /// Settings keyword validation against the installed vocabulary.
  KeywordCheck checkKeyword(String keyword) {
    return _voice?.checkKeyword(keyword) ?? tokens.checkKeyword(keyword, null);
  }

  /// Audio level 0..1, updated at high rate; listen separately to avoid
  /// rebuilding the whole tree.
  ValueListenable<double> get level => _level;

  void start() {
    if (_subscriptions.isNotEmpty) {
      return;
    }
    _subscriptions
      ..add(_client.messages.listen(_onMessage))
      ..add(_client.statusChanges.listen(_onStatus));
    final tts = _tts;
    if (tts != null) {
      _subscriptions.add(tts.onComplete.listen(_onSpoken));
    }
    _client.connect(_settings.wsUri);
    _dimmer?.start(_settings.dim);
    _startVoice();
    unawaited(_bootPack());
    _photos.setMember(_settings.activeMemberId);
    unawaited(_photos.boot(_settings.photoManifestUrl));
    _packTimer = Timer.periodic(
      SenPackDefaults.refreshEvery,
      (_) => unawaited(refreshPack()),
    );
    _updater?.start(_settings.updateUri, _settings.dim);
  }

  /// Ambient wake (app resumed, screen back on) refreshes the pack.
  void attachLifecycle() {
    _lifecycle ??= AppLifecycleListener(onResume: onAmbientWake);
  }

  void onAmbientWake() => unawaited(refreshPack());

  /// Background refresh from the configured URL: timer, wake and the
  /// hub's `pack_updated` push. Overlapping calls share one download.
  Future<PackSyncResult?> refreshPack() async {
    final url = _settings.knowledgePackUrl;
    if (_pack == null || url.isEmpty || _disposed) {
      return null;
    }
    return _packRun ??= syncPack(url).whenComplete(() => _packRun = null);
  }

  /// Cached pack first so Sen works offline, then a refresh when a URL
  /// is set.
  Future<void> _bootPack() async {
    final service = _pack;
    if (service == null) {
      return;
    }
    final cached = await service.loadCached();
    if (cached != null && !_disposed) {
      _registry.load(cached);
      notifyListeners();
    }
    final url = _settings.knowledgePackUrl;
    if (url.isEmpty || _disposed) {
      return;
    }
    await syncPack(url);
  }

  /// Settings "Sync now": downloads and applies the pack at [url].
  Future<PackSyncResult> syncPack(String url) async {
    final service = _pack;
    if (service == null) {
      return const PackSyncResult(PackSync.failed);
    }
    final result = await service.fetchAndApply(url);
    final pack = result.pack;
    if (result.status == PackSync.updated && pack != null && !_disposed) {
      _registry.load(pack);
      notifyListeners();
    }
    return result;
  }

  bool isPackUrl(String url) => SenPackService.parseUrl(url) != null;

  bool isUpdateUrl(String url) => AppUpdater.parseUrl(url) != null;

  /// Settings "Check for updates", against [candidate]'s endpoint when
  /// given.
  Future<UpdateCheck> checkUpdate([HubSettings? candidate]) async {
    final updater = _updater;
    if (updater == null) {
      return UpdateCheck.unsupported;
    }
    return updater.check(endpoint: candidate?.normalized().updateUri);
  }

  /// Update badge tap: the system installer for the downloaded APK.
  Future<InstallResult> installUpdate() async {
    return await _updater?.install() ?? InstallResult.unsupported;
  }

  bool isPhotoUrl(String url) => PhotoManifestService.parseUrl(url) != null;

  void _startVoice() {
    final voice = _voice;
    if (voice == null) {
      return;
    }
    _subscriptions.add(voice.events.listen(_onVoice));
    _installer?.progress.addListener(notifyListeners);
    unawaited(_bootVoice(voice));
  }

  Future<void> _bootVoice(WakeWordService voice) async {
    _setVoiceStatus(await voice.start(_settings.wakeConfig));
    await _applyKeepAlive();
    await installModel();
  }

  /// Downloads the keyword model if missing, then arms the wake word.
  /// Safe to call again after a failure (Settings retry button).
  Future<void> installModel() async {
    final installer = _installer;
    final voice = _voice;
    if (installer == null || voice == null) {
      return;
    }
    final model = await installer.ensureInstalled();
    if (model == null || _disposed) {
      return;
    }
    _setVoiceStatus(await voice.reloadModel());
  }

  /// Starts or stops the microphone foreground service to match settings.
  Future<void> _applyKeepAlive() async {
    final voice = _voice;
    final keepAlive = _keepAlive;
    if (voice == null || keepAlive == null) {
      return;
    }
    if (!_settings.alwaysListening || !_micAllowed) {
      voice.setBackgroundMode(BackgroundMode.releaseMic);
      await keepAlive.stop();
      return;
    }
    final running = await keepAlive.start();
    voice.setBackgroundMode(
      running ? BackgroundMode.keepListening : BackgroundMode.releaseMic,
    );
  }

  bool get _micAllowed {
    return switch (_voiceStatus) {
      VoiceStatus.noPermission || VoiceStatus.blocked || null => false,
      _ => true,
    };
  }

  void reconnect() => _client.connect(_settings.wsUri);

  bool transition(DisplayState next) {
    if (!canTransition(_state, next)) {
      return false;
    }
    _state = next;
    _onEnter(next);
    notifyListeners();
    return true;
  }

  SendResult sendText(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return SendResult.empty;
    }
    final gemini = _gemini;
    if (gemini != null && _settings.activeBrain == BrainMode.gemini) {
      return _askGemini(gemini, text);
    }
    if (!_client.send(HermesCodec.userText(text))) {
      return SendResult.offline;
    }
    if (!transition(DisplayState.thinking)) {
      _reply = '';
    }
    _transcript = text;
    notifyListeners();
    return SendResult.sent;
  }

  SendResult _askGemini(GeminiService gemini, String text) {
    _stopSpeech();
    if (_answerQuiz(text)) {
      return SendResult.sent;
    }
    final turn = ++_geminiTurn;
    if (!transition(DisplayState.thinking)) {
      _reply = '';
    }
    _turnBrain = BrainMode.gemini;
    _transcript = text;
    notifyListeners();
    unawaited(_runGemini(gemini, text, turn));
    return SendResult.sent;
  }

  /// Standalone voice turn: Gemini transcribes [wav] and answers.
  void _askGeminiAudio(GeminiService gemini, Uint8List wav) {
    final turn = ++_geminiTurn;
    _turnBrain = BrainMode.gemini;
    transition(DisplayState.thinking);
    unawaited(_runGemini(gemini, '', turn, audio: wav));
  }

  Future<void> _runGemini(
    GeminiService gemini,
    String spoken,
    int turn, {
    Uint8List? audio,
  }) async {
    final member = this.member;
    var text = spoken;
    final skill = SenSkill.detect(text) ?? _sessionSkill;
    final memory = _memory;
    final remembered = memory == null ? '' : await _recall(memory, member);
    if (_isStale(turn)) {
      return;
    }
    final context = _contextFor(remembered, skill, member, text);
    final key = _settings.geminiApiKey;
    final GeminiReply answer;
    try {
      answer = audio == null
          ? await gemini.ask(text, key, memoryContext: context)
          : await gemini.askAudio(audio, key, memoryContext: context);
    } on GeminiException catch (error) {
      if (_isStale(turn)) {
        return;
      }
      _lastError = error.message;
      _forceIdle();
      return;
    }
    if (_isStale(turn) || _state != DisplayState.thinking) {
      return;
    }
    if (audio != null) {
      text = answer.transcript;
      _transcript = text;
    }
    final content = skill?.parse(answer.text);
    _reply = content?.spoken ?? answer.text;
    _rich = content == null
        ? RichContent.parse(
            question: text,
            reply: answer.text,
            videos: answer.videos,
          )
        : RichContent.forSkill(question: text, skill: content);
    _session = content == null ? null : _rich;
    _quizPick = null;
    transition(DisplayState.speaking);
    unawaited(_speakAnswer(_reply, turn));
    if (content is RoleplayContent) {
      unawaited(_record(member, SkillKind.english, SkillOutcome.practiced));
    }
  }

  SenSkill? get _sessionSkill {
    final kind = _session?.skill?.kind;
    return kind == null ? null : SenSkill.of(kind);
  }

  /// Memory first, then the skill and what was said in it last turn; a
  /// knowledge pack skill or ritual when no built-in skill applies.
  String _contextFor(
    String memory,
    SenSkill? skill,
    MemberProfile member,
    String text,
  ) {
    final recap = _session?.skill;
    return [
      memory,
      ?skill?.instruction(member),
      if (skill == null) _registry.instructionFor(text, member, DateTime.now()),
      if (PhotoQuestion.matches(text)) _photos.describe(nameOf: _memberName),
      if (recap != null && recap.kind == skill?.kind) recap.recap,
    ].where((part) => part.isNotEmpty).join(_contextGap);
  }

  String _memberName(String id) {
    return _registry.has(id) ? _registry.byId(id).name : id;
  }

  /// Memory is a bonus; a broken database never blocks an answer.
  Future<String> _recall(SenMemoryService memory, MemberProfile member) async {
    try {
      return await memory.buildMemoryPrompt(member.id);
    } on Exception {
      return '';
    }
  }

  Future<void> _record(
    MemberProfile member,
    SkillKind skill,
    SkillOutcome outcome,
  ) async {
    try {
      await _memory?.recordSkill(member.id, skill, outcome);
    } on Exception {
      return;
    }
  }

  /// A typed or spoken "B" answers the open quiz locally.
  bool _answerQuiz(String text) {
    final session = _session;
    final quiz = session?.skill;
    if (quiz is! QuizContent || _quizPick != null) {
      return false;
    }
    final choice = quiz.choiceFrom(text);
    if (choice == null) {
      return false;
    }
    _rich = session;
    _forceIdle();
    pickQuiz(choice);
    return true;
  }

  /// Answers the shown quiz once and scores it for the active member.
  void pickQuiz(int index) {
    final quiz = _rich?.skill;
    if (quiz is! QuizContent || _quizPick != null) {
      return;
    }
    if (index < 0 || index >= quiz.options.length) {
      return;
    }
    _quizPick = index;
    notifyListeners();
    final outcome = quiz.isCorrect(index)
        ? SkillOutcome.correct
        : SkillOutcome.wrong;
    unawaited(_record(member, SkillKind.quiz, outcome));
  }

  /// Avatar tap: who Sen is talking to from the next turn on.
  void selectMember(String id) {
    if (id == _settings.activeMemberId || !_registry.has(id)) {
      return;
    }
    _settings = _settings.copyWith(activeMemberId: id);
    _photos.setMember(id);
    notifyListeners();
    unawaited(_settingsService.save(_settings));
  }

  /// Reads the start of a Gemini answer aloud via the hub; offline or on
  /// failure the text stays on screen until the watchdog.
  Future<void> _speakAnswer(String answer, int turn) async {
    final hubTts = _hubTts;
    final tts = _tts;
    final summary = spokenSummary(answer);
    if (hubTts == null || tts == null || summary.isEmpty) {
      return;
    }
    if (!_hubOnline) {
      debugPrint(_ttsOffline);
      return;
    }
    final audio = await hubTts.fetch(_settings.ttsUri, summary);
    if (_isStale(turn) || _state != DisplayState.speaking) {
      return;
    }
    if (audio == null) {
      debugPrint(_ttsFailed);
      return;
    }
    try {
      await tts.play(audio);
    } on Exception catch (error) {
      debugPrint('$_ttsPlayFailed: $error');
    }
  }

  bool _isStale(int turn) => _disposed || turn != _geminiTurn;

  void dismissRich() {
    if (_rich == null && _session == null) {
      return;
    }
    _rich = null;
    _session = null;
    _quizPick = null;
    notifyListeners();
  }

  /// "Save to Hermes": the current card into the Mac's Second Brain.
  Future<SaveResult> saveRich() async {
    final rich = _rich;
    final sync = _sync;
    if (rich == null || sync == null) {
      return SaveResult.failed;
    }
    return sync.save(_settings.saveUri, rich.toNote());
  }

  /// Mic button and wake word entry point: cue, listening, then capture.
  Future<ListenResult> listen() async {
    _stopSpeech();
    final voice = _voice;
    if (voice == null) {
      return wake() ? ListenResult.started : ListenResult.offline;
    }
    if (_state == DisplayState.listening || _starting) {
      return ListenResult.busy;
    }
    if (!_hubOnline && _voiceBrain != BrainMode.gemini) {
      await voice.endCapture();
      return ListenResult.offline;
    }
    _starting = true;
    try {
      return await _beginListening(voice);
    } finally {
      _starting = false;
    }
  }

  Future<ListenResult> _beginListening(WakeWordService voice) async {
    await voice.playCue();
    final status = await voice.beginCapture();
    _setVoiceStatus(status);
    if (status != VoiceStatus.ready) {
      await voice.endCapture();
      return _failureFor(status);
    }
    if (!wake()) {
      await voice.endCapture();
      return ListenResult.offline;
    }
    return ListenResult.started;
  }

  static ListenResult _failureFor(VoiceStatus status) {
    return switch (status) {
      VoiceStatus.noPermission ||
      VoiceStatus.blocked => ListenResult.noPermission,
      _ => ListenResult.micUnavailable,
    };
  }

  /// Gemini listens without the hub; the turn is then Gemini's so hub
  /// reconnect attempts do not end it.
  bool wake() {
    final sent = _client.send(HermesCodec.command(WireType.wake));
    if (!sent && _voiceBrain != BrainMode.gemini) {
      return false;
    }
    if (!transition(DisplayState.listening)) {
      return false;
    }
    if (!sent) {
      _turnBrain = BrainMode.gemini;
    }
    return true;
  }

  bool get _hubOnline => _connection == ConnectionStatus.connected;

  void cancel() {
    _geminiTurn++;
    _client.send(HermesCodec.command(WireType.cancel));
    _forceIdle();
  }

  Future<void> applySettings(HubSettings next) async {
    final normalized = next.normalized();
    final addressChanged = !normalized.sameAddress(_settings);
    final modeChanged = normalized.alwaysListening != _settings.alwaysListening;
    final photosChanged =
        normalized.photoManifestUrl != _settings.photoManifestUrl;
    _settings = normalized;
    await _settingsService.save(normalized);
    notifyListeners();
    if (addressChanged) {
      _client.connect(normalized.wsUri);
    }
    if (photosChanged) {
      unawaited(_photos.boot(normalized.photoManifestUrl));
    }
    _dimmer?.configure(normalized.dim);
    _updater?.configure(normalized.updateUri, normalized.dim);
    await _voice?.configure(normalized.wakeConfig);
    if (modeChanged) {
      await _applyKeepAlive();
    }
  }

  Future<bool> testConnection(HubSettings candidate) {
    return _client.probe(candidate.normalized().wsUri);
  }

  void _onEnter(DisplayState next) {
    _armWatchdog(next);
    if (next != DisplayState.speaking) {
      _stopSpeech();
    }
    if (next != DisplayState.listening) {
      unawaited(_voice?.endCapture());
    }
    if (next != DisplayState.idle) {
      _dimmer?.hold(BrightHold.turn);
    }
    if (next == DisplayState.idle) {
      _dimmer?.release(BrightHold.turn);
      unawaited(_releaseScreen());
      _turnBrain = BrainMode.hub;
      _transcript = '';
      _reply = '';
      _level.value = 0;
      return;
    }
    if (next == DisplayState.listening) {
      _capturePcm.clear();
      _transcript = '';
      _reply = '';
      _rich = null;
      return;
    }
    if (next == DisplayState.thinking) {
      _reply = '';
      _rich = null;
    }
  }

  void _armWatchdog(DisplayState current) {
    _watchdog?.cancel();
    if (current == DisplayState.idle) {
      return;
    }
    _watchdog = Timer(StateTiming.activeTimeout, _onWatchdog);
  }

  /// A long spoken reply is progress, not a silent hub.
  void _onWatchdog() {
    if (_speaking) {
      _armWatchdog(_state);
      return;
    }
    _forceIdle();
  }

  void _stopSpeech() {
    if (!_speaking) {
      return;
    }
    unawaited(_tts?.stop());
  }

  void _onSpoken(void _) {
    if (_state != DisplayState.speaking) {
      return;
    }
    transition(DisplayState.idle);
  }

  void _onMessage(HermesMessage message) {
    _armWatchdog(_state);
    switch (message) {
      case StateMessage(:final state):
        // The hub guesses speech length; playback end decides instead.
        if (state == DisplayState.idle && _speaking) {
          return;
        }
        transition(state);
      case SpeechMessage(:final text, :final audioBytes):
        _reply = text;
        _rich = RichContent.parse(question: _transcript, reply: text);
        _session = null;
        _quizPick = null;
        if (!transition(DisplayState.speaking)) {
          notifyListeners();
        }
        if (audioBytes != null && _state == DisplayState.speaking) {
          unawaited(_tts?.play(audioBytes));
        }
      case TranscriptMessage(:final text):
        _onTranscript(text);
      case LevelMessage(:final level):
        _level.value = level;
      case ErrorMessage(:final text):
        _lastError = text;
        _forceIdle();
      case PackUpdatedMessage():
        unawaited(refreshPack());
    }
  }

  /// A Gemini voice turn starts once the hub has transcribed it.
  void _onTranscript(String text) {
    final gemini = _gemini;
    final awaiting =
        _state == DisplayState.thinking && _turnBrain == BrainMode.hub;
    if (gemini != null && awaiting && _voiceBrain == BrainMode.gemini) {
      _askGemini(gemini, text);
      return;
    }
    _transcript = text;
    notifyListeners();
  }

  BrainMode get _voiceBrain {
    return _gemini == null ? BrainMode.hub : _settings.activeBrain;
  }

  void _onVoice(VoiceEvent event) {
    switch (event) {
      case WakeHeard():
        unawaited(_onWake());
      case SpeechAudio(:final pcm, :final level):
        if (_state != DisplayState.listening) {
          return;
        }
        _client.sendAudio(pcm);
        if (_voiceBrain == BrainMode.gemini) {
          _capturePcm.add(pcm);
        }
        _level.value = level;
      case CaptureDone(:final reason):
        _onCaptureDone(reason);
    }
  }

  Future<void> _onWake() async {
    await _wakeScreen();
    final result = await listen();
    if (result == ListenResult.started) {
      return;
    }
    await _voice?.endCapture();
    if (_state == DisplayState.idle) {
      _dimmer?.release(BrightHold.turn);
      await _releaseScreen();
    }
  }

  /// Screen on + above keyguard for this turn; full brightness first so
  /// the panel does not light up dimmed.
  Future<void> _wakeScreen() async {
    final screen = _screen;
    if (screen == null) {
      return;
    }
    _dimmer?.hold(BrightHold.turn);
    _screenWoken = true;
    _screenResult = await screen.wake();
  }

  Future<void> _releaseScreen() async {
    final screen = _screen;
    if (screen == null || !_screenWoken) {
      return;
    }
    _screenWoken = false;
    _screenResult = await screen.release();
  }

  void _onCaptureDone(CaptureEnd reason) {
    if (_state != DisplayState.listening) {
      return;
    }
    switch (reason) {
      case CaptureEnd.speechEnded:
      case CaptureEnd.maxLength:
        _endCapture();
      case CaptureEnd.noSpeech:
      case CaptureEnd.stopped:
        cancel();
    }
  }

  /// Hub transcribes when it heard the turn; otherwise Gemini hears the
  /// WAV itself.
  void _endCapture() {
    final gemini = _gemini;
    final hubHeard = _hubOnline && _turnBrain == BrainMode.hub;
    if (gemini == null || hubHeard || _voiceBrain != BrainMode.gemini) {
      _client.send(HermesCodec.audioEnd(_voiceBrain));
      transition(DisplayState.thinking);
      return;
    }
    final pcm = _capturePcm.takeBytes();
    _askGeminiAudio(gemini, ToneSynth.wav(Int16List.sublistView(pcm)));
  }

  void _setVoiceStatus(VoiceStatus status) {
    if (_disposed || status == _voiceStatus) {
      return;
    }
    _voiceStatus = status;
    notifyListeners();
  }

  void _onStatus(ConnectionStatus status) {
    _connection = status;
    if (status == ConnectionStatus.connected) {
      _lastError = null;
    }
    if (status != ConnectionStatus.connected && _turnBrain == BrainMode.hub) {
      _resetToIdle();
    }
    notifyListeners();
  }

  void _forceIdle() {
    if (!_resetToIdle()) {
      return;
    }
    notifyListeners();
  }

  bool _resetToIdle() {
    if (_state == DisplayState.idle) {
      return false;
    }
    _state = DisplayState.idle;
    _onEnter(DisplayState.idle);
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _watchdog?.cancel();
    _packTimer?.cancel();
    _lifecycle?.dispose();
    _updater?.dispose();
    _installer?.progress.removeListener(notifyListeners);
    unawaited(_keepAlive?.stop());
    unawaited(_releaseScreen());
    _dimmer?.dispose();
    _client.dispose();
    _voice?.dispose();
    unawaited(_tts?.dispose());
    _level.dispose();
    _photos.dispose();
    super.dispose();
  }
}
