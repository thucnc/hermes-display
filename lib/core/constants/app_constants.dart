/// Default hub connection values used until the user configures their own.
abstract final class HubDefaults {
  static const String scheme = 'ws';
  static const String host = 'localhost';
  static const int port = 8900;
  static const int slideIntervalSec = 20;
  static const double wakeSensitivity = 0.5;
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
