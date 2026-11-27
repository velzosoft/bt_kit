import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';

import '../profile/database_command.dart';
import '../profile/fault_command.dart';
import '../profile/reference_profile.dart';
import '../profile/stream_command.dart';

/// The reference profile as a local GATT service, and the state its
/// characteristics share. Every read and write goes through a handler, so
/// they can be counted.
final class ReferenceGatt {
  ReferenceGatt({
    required String info,
    required this.onStreamCommand,
    required this.onDatabaseCommand,
  }) : _info = ReferenceProfile.infoValue(info);

  final void Function(StreamCommand command) onStreamCommand;

  /// Asks for the extra service to be added or removed, after the write
  /// that asked for it has been answered.
  final void Function({required bool extraService}) onDatabaseCommand;
  final Uint8List _info;
  var _echo = Uint8List(0);

  /// The ATT error reads of the fault target fail with.
  GattError? fault;
  StreamCommand streamCommand = const StopStream();

  /// Whether the extra service is served.
  var hasExtraService = false;
  var reads = 0;
  var writes = 0;

  /// Requests answered with an ATT error.
  var errors = 0;

  late final characteristics = {
    for (final c in ReferenceCharacteristic.values) c: _characteristic(c),
  };

  late final includedService = LocalService(ReferenceProfile.includedService, [
    LocalCharacteristic(
      ReferenceProfile.includedCharacteristic,
      properties: const CharacteristicProperties.of(read: true),
      value: ReferenceProfile.includedValue,
    ),
  ], isPrimary: false);

  late final service = LocalService(
    ReferenceProfile.service,
    characteristics.values.toList(),
    includedServices: [includedService],
  );

  late final extraService = LocalService(ReferenceProfile.extraService, [
    LocalCharacteristic(
      ReferenceProfile.extraCharacteristic,
      properties: const CharacteristicProperties.of(read: true),
      value: ReferenceProfile.extraValue,
    ),
  ]);

  LocalCharacteristic operator [](ReferenceCharacteristic characteristic) =>
      characteristics[characteristic]!;

  LocalCharacteristic stream(StreamKind kind) =>
      this[switch (kind) {
        StreamKind.notify => ReferenceCharacteristic.notifyStream,
        StreamKind.indicate => ReferenceCharacteristic.indicateStream,
      }];

  LocalCharacteristic _characteristic(ReferenceCharacteristic c) {
    final properties = c.properties;
    final writable = properties.write || properties.writeWithoutResponse;
    return LocalCharacteristic(
      c.uuid,
      properties: properties,
      permissions: c == ReferenceCharacteristic.encrypted
          ? const {AttributePermission.readEncrypted}
          : null,
      onRead: properties.read ? (_) => _counted(() => _read(c)) : null,
      onWrite: writable
          ? (request) => _counted(() => _write(c, request.value))
          : null,
    );
  }

  T _counted<T>(T Function() handle) {
    try {
      return handle();
    } on GattException {
      errors++;
      rethrow;
    }
  }

  List<int> _read(ReferenceCharacteristic c) {
    reads++;
    return switch (c) {
      ReferenceCharacteristic.fixedValue => ReferenceProfile.fixedValue,
      ReferenceCharacteristic.echo => _echo,
      ReferenceCharacteristic.longValue => ReferenceProfile.longValue,
      ReferenceCharacteristic.encrypted => ReferenceProfile.encryptedValue,
      ReferenceCharacteristic.faultControl => FaultCommand.encode(fault),
      ReferenceCharacteristic.faultTarget => _faultTarget(),
      ReferenceCharacteristic.streamControl => streamCommand.encode(),
      ReferenceCharacteristic.info => _info,
      ReferenceCharacteristic.databaseControl => DatabaseCommand.encode(
        extraService: hasExtraService,
      ),
      ReferenceCharacteristic.notifyStream ||
      ReferenceCharacteristic.indicateStream => throw GattException(
        GattError.readNotPermitted,
        'read',
      ),
    };
  }

  List<int> _faultTarget() {
    if (fault case final fault?) throw GattException(fault, 'read');
    return ReferenceProfile.faultTargetValue;
  }

  void _write(ReferenceCharacteristic c, Uint8List value) {
    writes++;
    switch (c) {
      case ReferenceCharacteristic.echo:
        _echo = value;
      case ReferenceCharacteristic.faultControl:
        fault = FaultCommand.decode(value);
      case ReferenceCharacteristic.streamControl:
        streamCommand = StreamCommand.decode(value);
        onStreamCommand(streamCommand);
      case ReferenceCharacteristic.databaseControl:
        onDatabaseCommand(extraService: DatabaseCommand.decode(value));
      default:
        throw GattException(GattError.writeNotPermitted, 'write');
    }
  }
}
