import 'dart:async';
import 'dart:typed_data';

import 'package:bt_kit/bt_kit.dart';
import 'package:bt_radar/features/lab/peripheral/reference_gatt.dart';
import 'package:bt_radar/features/lab/peripheral/stream_pump.dart';
import 'package:bt_radar/features/lab/profile/reference_profile.dart';
import 'package:bt_radar/features/lab/profile/stream_command.dart';
import 'package:bt_radar/features/lab/profile/stream_packet.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Central implements Central {
  @override
  String get id => 'central';

  @override
  int get maximumUpdateLength => 20;

  @override
  CentralHandle get native => throw UnimplementedError();
}

void main() {
  final central = _Central();
  late List<StreamCommand> commands;
  late List<bool> databaseCommands;
  late ReferenceGatt gatt;

  setUp(() {
    commands = [];
    databaseCommands = [];
    gatt = ReferenceGatt(
      info: 'test 1.0',
      onStreamCommand: commands.add,
      onDatabaseCommand: ({required extraService}) =>
          databaseCommands.add(extraService),
    );
  });

  FutureOr<List<int>> read(ReferenceCharacteristic c) =>
      gatt[c].onRead!(ReadRequest(central, gatt[c]));

  FutureOr<void> write(ReferenceCharacteristic c, List<int> value) =>
      gatt[c].onWrite!(
        WriteRequest(
          central,
          gatt[c],
          Uint8List.fromList(value),
          withResponse: true,
        ),
      );

  Matcher rejectsWith(GattError error) =>
      throwsA(isA<GattException>().having((e) => e.error, 'error', error));

  test('serves one service with every characteristic', () {
    expect(gatt.service.uuid, ReferenceProfile.service);
    expect(
      gatt.service.characteristics.map((c) => c.uuid),
      ReferenceCharacteristic.values.map((c) => c.uuid),
    );
  });

  test('only the encrypted value needs an encrypted link', () {
    expect(gatt[ReferenceCharacteristic.encrypted].permissions, {
      AttributePermission.readEncrypted,
    });
    expect(gatt[ReferenceCharacteristic.fixedValue].permissions, {
      AttributePermission.read,
    });
  });

  test('serves the fixed values and its info', () async {
    expect(
      await read(ReferenceCharacteristic.fixedValue),
      ReferenceProfile.fixedValue,
    );
    expect(
      await read(ReferenceCharacteristic.longValue),
      ReferenceProfile.longValue,
    );
    expect(
      ReferenceProfile.describeInfo(await read(ReferenceCharacteristic.info)),
      'test 1.0',
    );
  });

  test('echoes what was written', () async {
    expect(await read(ReferenceCharacteristic.echo), isEmpty);
    await write(ReferenceCharacteristic.echo, [1, 2, 3]);
    expect(await read(ReferenceCharacteristic.echo), [1, 2, 3]);
    expect(gatt.writes, 1);
    expect(gatt.reads, 2);
  });

  test('a fault makes reads of the target fail until cleared', () async {
    await write(ReferenceCharacteristic.faultControl, [0x02]);
    expect(await read(ReferenceCharacteristic.faultControl), [0x02]);
    expect(
      () => read(ReferenceCharacteristic.faultTarget),
      rejectsWith(GattError.readNotPermitted),
    );
    expect(gatt.errors, 1);
    await write(ReferenceCharacteristic.faultControl, [0]);
    expect(
      await read(ReferenceCharacteristic.faultTarget),
      ReferenceProfile.faultTargetValue,
    );
  });

  test('stream control commands reach the pump', () async {
    await write(ReferenceCharacteristic.streamControl, [0x01, 50, 0]);
    await write(ReferenceCharacteristic.streamControl, [0x00]);
    expect(commands, const [StartStream(StreamKind.notify, 50), StopStream()]);
    expect(await read(ReferenceCharacteristic.streamControl), [0x00]);
  });

  test('invalid commands are rejected with an ATT error', () {
    expect(
      () => write(ReferenceCharacteristic.streamControl, [0x09]),
      rejectsWith(GattError.valueNotAllowed),
    );
    expect(commands, isEmpty);
    expect(gatt.errors, 1);
  });

  test('the pump sends numbered packets at its rate until stopped', () async {
    final sent = <StreamPacket>[];
    final pump = StreamPump((_, value) async {
      sent.add(StreamPacket.decode(value)!);
    });
    pump.start(
      gatt[ReferenceCharacteristic.notifyStream],
      const StartStream(StreamKind.notify, 200),
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));
    pump.stop();
    final count = sent.length;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(sent, hasLength(count));
    expect(count, inInclusiveRange(10, 40));
    expect(
      [for (final p in sent) p.sequence],
      [for (var i = 0; i < count; i++) i],
    );
    expect(sent.last.timestampMicros, greaterThan(sent.first.timestampMicros));
    expect(pump.command, isNull);
  });

  group('database control', () {
    test(
      'asks for the extra service and reports whether it is served',
      () async {
        await write(ReferenceCharacteristic.databaseControl, [0x01]);
        expect(databaseCommands, [true]);
        expect(await read(ReferenceCharacteristic.databaseControl), [0x00]);
        gatt.hasExtraService = true;
        expect(await read(ReferenceCharacteristic.databaseControl), [0x01]);
      },
    );

    test('rejects invalid commands', () {
      expect(
        () => write(ReferenceCharacteristic.databaseControl, [0x02]),
        rejectsWith(GattError.valueNotAllowed),
      );
      expect(
        () => write(ReferenceCharacteristic.databaseControl, []),
        rejectsWith(GattError.invalidAttributeValueLength),
      );
      expect(databaseCommands, isEmpty);
    });

    test('the extra service has one readable characteristic', () {
      expect(gatt.extraService.uuid, ReferenceProfile.extraService);
      expect(
        gatt.extraService.characteristics.single.value,
        ReferenceProfile.extraValue,
      );
    });
  });
}
