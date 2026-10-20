import 'dart:math';

/// Unique transaction identifier: `FP` + digits (e.g. FP100001).
///
/// Generation uses a cryptographically secure random number so ids are
/// unique across devices and app restarts without coordination.
class TransactionId {
  TransactionId._();

  static final RegExp _pattern = RegExp(r'^FP\d{6,16}$');
  static final Random _rng = Random.secure();

  static bool isValid(String? id) => id != null && _pattern.hasMatch(id);

  /// Generates a new id such as FP382910472.
  static String generate() {
    // 9 random digits => matches ^FP\d{6,16}$ with room to spare.
    final n = _rng.nextInt(900000000) + 100000000;
    return 'FP$n';
  }

  /// Generates a new id, retrying if [isTaken] reports a collision
  /// (e.g. when the id already exists in local storage).
  static String generateUnique(bool Function(String id) isTaken) {
    for (var i = 0; i < 10; i++) {
      final id = generate();
      if (!isTaken(id)) return id;
    }
    throw StateError('Unable to generate a unique transaction id');
  }
}
