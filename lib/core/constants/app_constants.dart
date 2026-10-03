import '../members/member_profile.dart';
import '../state/brain_mode.dart';

/// Default hub connection values used until the user configures their own.
abstract final class HubDefaults {
  static const String scheme = 'ws';
  static const String host = 'localhost';
  static const int port = 8901;
  static const int slideIntervalSec = 20;
  static const double wakeSensitivity = 0.8;
  static const String wakeKeyword = 'HELLO SEN';
  static const bool alwaysListening = true;
  static const String geminiApiKey = '';

  /// Effective only once a Gemini key is set; the hub otherwise.
  static const BrainMode brainMode = BrainMode.gemini;
  static const String activeMemberId = MemberProfile.defaultId;

  /// Empty: no remote knowledge pack, built-in family and skills.
  static const String knowledgePackUrl = '';

  /// Empty: the hub's [UpdateDefaults.latestPath].
  static const String updateUrl = '';

  /// Empty: placeholder slideshow instead of family photos.
  static const String photoManifestUrl = '';
}

/// Accepted ranges for user-editable settings.
abstract final class SettingsLimits {
  static const int minPort = 1;
  static const int maxPort = 65535;
  static const int minSlideSec = 5;
  static const int maxSlideSec = 120;
  static const double minSensitivity = 0;
  static const double maxSensitivity = 1;
}

abstract final class NetworkTiming {
  static const Duration connectTimeout = Duration(seconds: 5);
  static const Duration probeTimeout = Duration(seconds: 4);
  static const Duration pingInterval = Duration(seconds: 15);
  static const Duration backoffBase = Duration(seconds: 1);
  static const Duration backoffMax = Duration(seconds: 30);
  static const double backoffFactor = 2;
  static const double backoffJitter = 0.2;
  static const int backoffMaxExponent = 16;
}

abstract final class StateTiming {
  /// Fallback to idle when the hub goes silent mid-interaction.
  static const Duration activeTimeout = Duration(seconds: 45);
}

/// Capture format shared by the mic, the keyword spotter and the hub.
abstract final class AudioSpec {
  static const int sampleRate = 16000;
  static const int channels = 1;
  static const int bytesPerSample = 2;
  static const int int16Max = 32768;
}

abstract final class VoiceTiming {
  /// Trailing silence that ends an utterance once speech was heard.
  static const Duration endSilence = Duration(milliseconds: 1200);

  /// Give up if the user never starts talking after the cue.
  static const Duration noSpeech = Duration(seconds: 8);

  /// Give up if user does not follow up after assistant speaks.
  static const Duration followUpNoSpeech = Duration(seconds: 10);

  /// Silence before microphone re-opens after TTS to avoid acoustic feedback.
  static const Duration echoTail = Duration(milliseconds: 300);

  /// Hard cap on a single utterance.
  static const Duration maxUtterance = Duration(seconds: 15);
}

abstract final class VoiceLevels {
  /// RMS (0..1) above which a frame counts as speech.
  static const double speechRms = 0.012;

  /// Scales RMS into the 0..1 range the waveform expects.
  static const double meterGain = 8;
}

abstract final class WakeTuning {
  /// Sensitivity 0..1 maps linearly onto this spotter threshold range;
  /// higher sensitivity means a lower threshold.
  /// Lowered for Vietnamese "Hey Sen", which scores weaker than English.
  static const double strictThreshold = 0.25;
  static const double looseThreshold = 0.03;
  static const int numThreads = 1;

  /// Boost for keyword paths during decoding.
  static const double keywordsScore = 2.0;
  static const int defaultTrailingBlanks = 1;
  static const int minTrailingBlanks = 1;
  static const int maxTrailingBlanks = 5;
}

/// Night dimming defaults: on, 23:00 to 06:00 local, 5% backlight.
abstract final class DimDefaults {
  static const bool enabled = true;
  static const int startHour = 23;
  static const int endHour = 6;
  static const double level = 0.05;
}

abstract final class DimLimits {
  static const int minHour = 0;
  static const int maxHour = 23;

  /// 0 turns the backlight fully off on some panels.
  static const double minLevel = 0.01;
  static const double maxLevel = 0.5;
}

abstract final class DimTiming {
  static const Duration tick = Duration(minutes: 1);

  /// How long a touch keeps a dimmed screen at full brightness.
  static const Duration touchHold = Duration(seconds: 30);
}

abstract final class GeminiDefaults {
  static const String host = 'generativelanguage.googleapis.com';
  static const String model = 'gemini-3.8-flash';
  static const String pathPrefix = '/v1beta/models/';
  static const String action = ':generateContent';
  static const Duration timeout = Duration(seconds: 30);
}

/// Bidirectional speech-to-speech over WebSocket; no hub needed.
abstract final class GeminiLiveDefaults {
  static const String scheme = 'wss';
  static const String path =
      '/ws/google.ai.generativelanguage.v1alpha.GenerativeService'
      '.BidiGenerateContent';
  static const String model = 'models/gemini-3.8-live';

  /// Prebuilt voices: Puck, Aoede, Fenrir, Kore, Leda.
  /// Aoede: upbeat, cheerful, bright female voice.
  static const String voice = 'Aoede';
  static const String inputMime = 'audio/pcm;rate=16000';

  /// Used when a reply chunk's mime type names no rate.
  static const int outputRate = 24000;
  static const Duration setupTimeout = Duration(seconds: 8);

  /// Reply audio buffered before each WAV segment starts playing.
  static const Duration startBuffer = Duration(milliseconds: 600);

  /// Idle session closed after this; the next wake reconnects.
  static const Duration keepWarm = Duration(minutes: 5);
}

/// Hub HTTP endpoint for "Save to Hermes"; shares the WebSocket host:port.
abstract final class SyncDefaults {
  static const String scheme = 'http';
  static const String savePath = '/save';
  static const Duration timeout = Duration(seconds: 10);
}

/// Remote `sen-pack.json` download (GitHub Raw, Gist, Pages, hub...).
abstract final class SenPackDefaults {
  static const Duration timeout = Duration(seconds: 10);
  static const List<String> schemes = ['http', 'https'];

  /// Background re-check; cheap thanks to ETag/304.
  static const Duration refreshEvery = Duration(minutes: 30);
}

/// APK over-the-air updates from `GET /api/app/latest`.
abstract final class UpdateDefaults {
  static const String scheme = 'http';
  static const String latestPath = '/api/app/latest';
  static const List<String> schemes = ['http', 'https'];
  static const Duration checkTimeout = Duration(seconds: 10);

  /// Abort when the download stalls mid-file.
  static const Duration idleTimeout = Duration(seconds: 30);

  /// How often the nightly check looks at the clock.
  static const Duration tick = Duration(minutes: 15);

  /// At most one nightly check per dim window.
  static const Duration nightlyGap = Duration(hours: 12);
  static const int maxApkBytes = 300 * 1024 * 1024;

  /// Under the app cache dir; must match `res/xml/update_paths.xml`.
  static const String dirName = 'updates';
  static const String filePrefix = 'hermes-display-';
  static const String fileSuffix = '.apk';
  static const String partSuffix = '.part';
}

/// Hub HTTP endpoint that speaks Gemini answers; shares the hub host:port.
abstract final class HubTtsDefaults {
  static const String path = '/tts';
  static const String textParam = 'text';
  static const Duration timeout = Duration(seconds: 15);
}

/// Family photo frame: `photos.json` download and on-disk image cache.
abstract final class PhotoDefaults {
  static const Duration manifestTimeout = Duration(seconds: 10);
  static const Duration downloadTimeout = Duration(seconds: 30);

  /// Manifest re-checked this often while the slideshow runs.
  static const Duration refreshEvery = Duration(hours: 1);

  /// LRU cap for downloaded photos.
  static const int cacheBytes = 300 * 1024 * 1024;
  static const String cacheDir = 'photo_cache';

  /// Shown when no family manifest is configured.
  static const List<String> deck = [
    'https://picsum.photos/seed/hermes-1/1920/1280',
    'https://picsum.photos/seed/hermes-2/1920/1280',
    'https://picsum.photos/seed/hermes-3/1920/1280',
    'https://picsum.photos/seed/hermes-4/1920/1280',
    'https://picsum.photos/seed/hermes-5/1920/1280',
    'https://picsum.photos/seed/hermes-6/1920/1280',
  ];
}
