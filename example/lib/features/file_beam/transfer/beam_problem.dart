import 'dart:async';

import 'package:bt_kit/bt_kit.dart';

import '../protocol/beam_frame.dart';

/// Something that stopped a transfer, in words a person can act on.
final class BeamProblem {
  const BeamProblem(this.title, this.message, {this.needsSettings = false});

  factory BeamProblem.of(Object error) => switch (error) {
    BluetoothException() => _bluetooth(error),
    BeamFormatException(:final failure) => _format(failure),
    TimeoutException() => noAnswer,
    _ => BeamProblem('Something went wrong', '$error'),
  };

  static const permission = BeamProblem(
    'Bluetooth permission is off',
    'Receiving needs permission to advertise and accept connections. '
        'Allow it in the system settings.',
    needsSettings: true,
  );

  static const unsupported = BeamProblem(
    'This phone cannot receive',
    'Receiving needs the Bluetooth peripheral role and L2CAP channels, '
        'which this phone does not offer. It can still send.',
  );

  static const noAnswer = BeamProblem(
    'No answer',
    'The other phone did not answer in time. Is File beam still open on it?',
  );

  static const notReceiving = BeamProblem(
    'That phone is not receiving',
    'It stopped offering File beam. Ask its owner to tap Receive again.',
  );

  static const senderLeft = BeamProblem(
    'The sender walked away',
    'The connection dropped before the whole file arrived. Keep the phones '
        'close and try again.',
  );

  static const receiverLeft = BeamProblem(
    'The receiver walked away',
    'The connection dropped before the whole file was sent. Keep the phones '
        'close and try again.',
  );

  static const rejected = BeamProblem(
    'Checksum failed',
    'The receiver got a damaged copy and threw it away. Try again.',
  );

  final String title;
  final String message;

  /// Whether the way out is the app's page in the system settings.
  final bool needsSettings;

  static BeamProblem _bluetooth(BluetoothException error) => switch (error) {
    BluetoothUnavailableException() => const BeamProblem(
      'Bluetooth is off',
      'Turn Bluetooth on and try again.',
    ),
    BluetoothPermissionException() => const BeamProblem(
      'Bluetooth permission is off',
      'Allow Bluetooth for this app in the system settings.',
      needsSettings: true,
    ),
    UnsupportedFeatureException(:final message) => BeamProblem(
      'Not available on this phone',
      message,
    ),
    ScanException(:final message) => BeamProblem('The scan stopped', message),
    AdvertisingException(:final message) => BeamProblem(
      'Could not start advertising',
      message,
    ),
    ConnectionException() => const BeamProblem(
      'Could not connect',
      'The other phone did not accept the connection. Keep the phones close '
          'and try again.',
    ),
    BondException(:final message) => BeamProblem('Pairing failed', message),
    RangingException(:final message) => BeamProblem(
      'Distance unavailable',
      message,
    ),
    DisconnectedException() => const BeamProblem(
      'The connection dropped',
      'The other phone went out of range or closed File beam.',
    ),
    AttributeInvalidatedException() => const BeamProblem(
      'The other phone changed',
      'It changed its Bluetooth services mid-transfer. Start again.',
    ),
    GattException(:final error) => BeamProblem(
      'The other phone refused',
      'It answered with the Bluetooth error "${error.name}".',
    ),
    NativeOperationException(:final message) => BeamProblem(
      'Bluetooth refused',
      message,
    ),
    OperationTimeoutException() => noAnswer,
    OperationCancelledException() => const BeamProblem(
      'Cancelled',
      'The transfer was cancelled.',
    ),
  };

  static BeamProblem _format(BeamFailure failure) => switch (failure) {
    BeamFailure.checksumMismatch => const BeamProblem(
      'Checksum failed',
      'The file arrived damaged, so it was thrown away. Try again.',
    ),
    BeamFailure.truncated => senderLeft,
    BeamFailure.unsupportedVersion => const BeamProblem(
      'Different versions',
      'The other phone runs a different version of File beam. Update the '
          'app on both phones.',
    ),
    BeamFailure.tooLarge => const BeamProblem(
      'Too large',
      'The file is larger than File beam accepts.',
    ),
    BeamFailure.badMagic ||
    BeamFailure.badName ||
    BeamFailure.unexpectedBytes => const BeamProblem(
      'Not a File beam transfer',
      'The other side sent something File beam does not understand.',
    ),
  };
}
