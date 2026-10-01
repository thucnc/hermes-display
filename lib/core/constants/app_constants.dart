/// Default hub connection values used until the user configures their own.
abstract final class HubDefaults {
  static const String scheme = 'ws';
  static const String host = 'localhost';
  static const int port = 8900;
  static const int slideIntervalSec = 20;
  static const double wakeSensitivity = 0.7;
  static const String wakeKeyword = 'HEY SEN';
  static const bool alwaysListening = true;
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
  static const Duration noSpeech = Duration(seconds: 6);

  /// Hard cap on a single utterance.
  static const Duration maxUtterance = Duration(seconds: 15);
}

abstract final class VoiceLevels {
  /// RMS (0..1) above which a frame counts as speech.
  static const double speechRms = 0.02;

  /// Scales RMS into the 0..1 range the waveform expects.
  static const double meterGain = 8;
}

abstract final class WakeTuning {
  /// Sensitivity 0..1 maps linearly onto this spotter threshold range;
  /// higher sensitivity means a lower threshold.
  static const double strictThreshold = 0.3;
  static const double looseThreshold = 0.05;
  static const int numThreads = 1;

  /// Boost for keyword paths during decoding.
  static const double keywordsScore = 1.5;
  static const int defaultTrailingBlanks = 3;
  static const int minTrailingBlanks = 1;
  static const int maxTrailingBlanks = 5;
}
