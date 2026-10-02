import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/constants/app_constants.dart';
import '../core/media/rich_content.dart';

class GeminiReply {
  const GeminiReply({
    required this.text,
    this.videos = const [],
    this.transcript = '',
  });

  /// Videos are taken from [text] only.
  factory GeminiReply.of(String text, {String transcript = ''}) {
    return GeminiReply(
      text: text,
      videos: YouTubeVideo.extract(text),
      transcript: transcript,
    );
  }

  final String text;

  /// What Gemini heard in an audio question; empty for text questions.
  final String transcript;

  /// YouTube links from the answer text and its search sources.
  final List<YouTubeVideo> videos;
}

class GeminiException implements Exception {
  const GeminiException(this.message);
  final String message;

  @override
  String toString() => 'GeminiException: $message';
}

abstract interface class GeminiService {
  static const String systemPrompt =
      'Bạn là Sen, trợ lý màn hình thông minh. Trả lời ngắn gọn, súc tích, '
      'thân thiện bằng tiếng Việt. Nếu người dùng hỏi về công thức nấu ăn, '
      'hướng dẫn hoặc tìm kiếm video, hãy cung cấp công thức chuẩn kèm link '
      'video YouTube cụ thể.';

  /// [memoryContext] goes before [systemPrompt]: who is talking, their
  /// memories and the active skill. Throws [GeminiException] on a missing
  /// key, network or API failure.
  Future<GeminiReply> ask(
    String prompt,
    String apiKey, {
    String memoryContext = '',
  });

  /// Marks the transcript line Gemini writes before an audio answer.
  static const String transcriptTag = 'HỎI:';

  static const String audioPrompt =
      'Câu hỏi nằm trong đoạn ghi âm đính kèm. Dòng đầu tiên chép lại '
      'nguyên văn câu hỏi, bắt đầu bằng "$transcriptTag". Sau đó xuống '
      'dòng và trả lời.';

  /// [wav] is the recorded question (PCM16 mono WAV); Gemini transcribes
  /// and answers in one call, no hub needed. Throws like [ask].
  Future<GeminiReply> askAudio(
    Uint8List wav,
    String apiKey, {
    String memoryContext = '',
  });
}

abstract final class _Key {
  static const String apiKey = 'key';
  static const String system = 'system_instruction';
  static const String contents = 'contents';
  static const String role = 'role';
  static const String user = 'user';
  static const String parts = 'parts';
  static const String text = 'text';
  static const String tools = 'tools';
  static const String googleSearch = 'google_search';
  static const String candidates = 'candidates';
  static const String content = 'content';
  static const String grounding = 'groundingMetadata';
  static const String chunks = 'groundingChunks';
  static const String web = 'web';
  static const String uri = 'uri';
  static const String inlineData = 'inlineData';
  static const String mimeType = 'mimeType';
  static const String data = 'data';
}

abstract final class _Error {
  static const String noKey = 'Chưa có Gemini API key';
  static const String network = 'Không gọi được Gemini';
  static const String http = 'Gemini lỗi HTTP';
  static const String empty = 'Gemini không trả lời';
}

/// Direct REST client with Google Search grounding.
final class HttpGeminiService implements GeminiService {
  HttpGeminiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const int _httpOk = 200;
  static const String _jsonType = 'application/json; charset=utf-8';
  static const String _contextGap = '\n\n';
  static const String _wavType = 'audio/wav';
  static const String _newline = '\n';
  static const String _markdownBold = '*';

  @override
  Future<GeminiReply> ask(
    String prompt,
    String apiKey, {
    String memoryContext = '',
  }) async {
    return _post(apiKey, [
      {_Key.text: prompt},
    ], memoryContext);
  }

  @override
  Future<GeminiReply> askAudio(
    Uint8List wav,
    String apiKey, {
    String memoryContext = '',
  }) async {
    final reply = await _post(apiKey, [
      {_Key.text: GeminiService.audioPrompt},
      {
        _Key.inlineData: {
          _Key.mimeType: _wavType,
          _Key.data: base64Encode(wav),
        },
      },
    ], memoryContext);
    return _splitTranscript(reply);
  }

  Future<GeminiReply> _post(
    String apiKey,
    List<Map<String, Object?>> parts,
    String memoryContext,
  ) async {
    if (apiKey.isEmpty) {
      throw const GeminiException(_Error.noKey);
    }
    final http.Response response;
    try {
      response = await _client
          .post(
            _endpoint(apiKey),
            headers: {'content-type': _jsonType},
            body: jsonEncode(_payload(parts, memoryContext)),
          )
          .timeout(GeminiDefaults.timeout);
    } on Exception {
      // ClientException, TimeoutException and TLS errors alike.
      throw const GeminiException(_Error.network);
    }
    if (response.statusCode != _httpOk) {
      throw GeminiException('${_Error.http} ${response.statusCode}');
    }
    return _parse(utf8.decode(response.bodyBytes));
  }

  static Uri _endpoint(String apiKey) {
    return Uri.https(
      GeminiDefaults.host,
      '${GeminiDefaults.pathPrefix}${GeminiDefaults.model}'
      '${GeminiDefaults.action}',
      {_Key.apiKey: apiKey},
    );
  }

  /// Moves a leading "[transcriptTag] ..." line out of the answer.
  static GeminiReply _splitTranscript(GeminiReply reply) {
    final text = reply.text;
    final cut = text.indexOf(_newline);
    final first = (cut < 0 ? text : text.substring(0, cut))
        .replaceAll(_markdownBold, '')
        .trim();
    if (!first.startsWith(GeminiService.transcriptTag)) {
      return reply;
    }
    final rest = cut < 0 ? '' : text.substring(cut + 1).trim();
    if (rest.isEmpty) {
      return reply;
    }
    return GeminiReply(
      text: rest,
      videos: reply.videos,
      transcript: first.substring(GeminiService.transcriptTag.length).trim(),
    );
  }

  static Map<String, Object?> _payload(
    List<Map<String, Object?>> parts,
    String context,
  ) {
    final system = context.isEmpty
        ? GeminiService.systemPrompt
        : '$context$_contextGap${GeminiService.systemPrompt}';
    return {
      _Key.system: {
        _Key.parts: [
          {_Key.text: system},
        ],
      },
      _Key.contents: [
        {_Key.role: _Key.user, _Key.parts: parts},
      ],
      _Key.tools: [
        {_Key.googleSearch: <String, Object?>{}},
      ],
    };
  }

  static GeminiReply _parse(String raw) {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      throw const GeminiException(_Error.empty);
    }
    final candidate = _first(_map(json)?[_Key.candidates]);
    final parts = _map(candidate?[_Key.content])?[_Key.parts];
    final text = [
      if (parts is List)
        for (final part in parts) _map(part)?[_Key.text] ?? '',
    ].join().trim();
    if (text.isEmpty) {
      throw const GeminiException(_Error.empty);
    }
    final sources = _sourceUris(_map(candidate?[_Key.grounding]));
    final seen = <String>{};
    final videos = [
      ...YouTubeVideo.extract(text),
      ...YouTubeVideo.extract(sources),
    ].where((video) => seen.add(video.id)).toList();
    return GeminiReply(text: text, videos: videos);
  }

  static String _sourceUris(Map<String, dynamic>? grounding) {
    final chunks = grounding?[_Key.chunks];
    if (chunks is! List) {
      return '';
    }
    return [
      for (final chunk in chunks) _map(_map(chunk)?[_Key.web])?[_Key.uri] ?? '',
    ].join(' ');
  }

  static Map<String, dynamic>? _map(Object? value) {
    return value is Map<String, dynamic> ? value : null;
  }

  static Map<String, dynamic>? _first(Object? value) {
    if (value is! List || value.isEmpty) {
      return null;
    }
    return _map(value.first);
  }
}
