import 'dart:async';

/// Every consumer that opens the microphone.
enum MicOwner { wakeWord, voiceTurn }

/// Proof of ownership; only the matching lease can release the mic.
final class MicLease {
  const MicLease._(this.owner, this._id);

  final MicOwner owner;
  final int _id;
}

/// Process-wide gate so two recorders never hold the mic at once. Wake word
/// releases its lease before a voice turn acquires one and takes it back
/// once the turn ends.
class MicCoordinator {
  final StreamController<MicOwner?> _changes =
      StreamController<MicOwner?>.broadcast();
  MicLease? _active;
  int _nextId = 0;

  MicOwner? get owner => _active?.owner;

  /// Fires with the new owner, or null when the mic becomes free.
  Stream<MicOwner?> get changes => _changes.stream;

  /// Null while someone else holds the mic.
  MicLease? tryAcquire(MicOwner owner) {
    if (_active != null) {
      return null;
    }
    final lease = MicLease._(owner, _nextId++);
    _active = lease;
    _changes.add(owner);
    return lease;
  }

  /// False for a stale lease; the current owner keeps the mic.
  bool release(MicLease lease) {
    if (_active?._id != lease._id) {
      return false;
    }
    _active = null;
    _changes.add(null);
    return true;
  }
}
