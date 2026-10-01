import 'package:hermes_display/services/audio/mic_keep_alive.dart';

enum KeepAliveHealth { ok, refused }

class FakeKeepAlive implements MicKeepAlive {
  FakeKeepAlive({this.health = KeepAliveHealth.ok});

  KeepAliveHealth health;
  int starts = 0;
  int stops = 0;
  bool running = false;

  @override
  Future<bool> start() async {
    starts++;
    running = health == KeepAliveHealth.ok;
    return running;
  }

  @override
  Future<void> stop() async {
    stops++;
    running = false;
  }
}
