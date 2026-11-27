import 'package:flutter/foundation.dart';

import '../../../bluetooth/hex.dart';

/// A Lab check that failed without a Bluetooth error.
sealed class LabFailure implements Exception {
  const LabFailure(this.message);

  final String message;

  String get kind;

  @override
  String toString() => '$kind: $message';
}

final class ValueMismatch extends LabFailure {
  ValueMismatch(String what, List<int> expected, List<int> actual)
    : super(
        '$what: expected ${expected.length} bytes '
        '(${expected.toHex(max: 12)}), got ${actual.length} '
        '(${actual.toHex(max: 12)})',
      );

  static void check(String what, List<int> actual, List<int> expected) {
    if (!listEquals(actual, expected)) {
      throw ValueMismatch(what, expected, actual);
    }
  }

  @override
  String get kind => 'ValueMismatch';
}

final class ProfileMismatch extends LabFailure {
  ProfileMismatch(List<String> problems)
    : super('Not the reference profile: ${problems.join('; ')}');

  @override
  String get kind => 'ProfileMismatch';
}

final class DeadlineExceeded extends LabFailure {
  const DeadlineExceeded(super.message);

  @override
  String get kind => 'DeadlineExceeded';
}

final class UnexpectedResult extends LabFailure {
  const UnexpectedResult(super.message);

  @override
  String get kind => 'UnexpectedResult';
}
