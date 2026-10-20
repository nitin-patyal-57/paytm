import 'protocol_message.dart';

/// Detects duplicate Bluetooth messages.
///
/// A duplicate (same content re-sent after a retry, reconnect or double
/// notification) is rejected so downstream logic runs exactly once.
/// Entries are bounded by [capacity] and expire after [ttl].
class MessageDeduplicator {
  MessageDeduplicator(
      {this.capacity = 128, this.ttl = const Duration(minutes: 5)})
      : assert(capacity > 0);

  final int capacity;
  final Duration ttl;

  final Map<String, DateTime> _seen = <String, DateTime>{};

  int get size => _seen.length;

  /// Returns true when [message] is seen for the first time (i.e. it should
  /// be processed); false when it is a duplicate.
  bool accept(ProtocolMessage message, {DateTime? now}) =>
      acceptKey(message.dedupKey, now: now);

  bool acceptKey(String key, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    _evictExpired(reference);
    final previous = _seen[key];
    if (previous != null && reference.difference(previous) <= ttl) {
      return false;
    }
    _seen[key] = reference;
    while (_seen.length > capacity) {
      _seen.remove(_seen.keys.first);
    }
    return true;
  }

  /// True if [message] was already accepted (without recording it).
  bool isDuplicate(ProtocolMessage message, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    _evictExpired(reference);
    final previous = _seen[message.dedupKey];
    return previous != null && reference.difference(previous) <= ttl;
  }

  void _evictExpired(DateTime now) {
    _seen.removeWhere((_, at) => now.difference(at) > ttl);
  }

  void reset() => _seen.clear();
}
