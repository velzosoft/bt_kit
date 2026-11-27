import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../central/native_types.dart';
import '../core/bluetooth_uuid.dart';
import '../core/exceptions.dart';
import '../models/attribute_permission.dart';
import '../models/characteristic_properties.dart';

/// Answers a read with the attribute's full value. Long reads are served
/// from it in pieces.
typedef ReadHandler = FutureOr<List<int>> Function(ReadRequest request);

/// Accepts a write. Throw a [GattException] to reject it with an ATT error.
typedef WriteHandler = FutureOr<void> Function(WriteRequest request);

/// A remote device connected to this device's GATT server.
abstract interface class Central {
  /// Android: the MAC address. iOS: a per-app UUID.
  String get id;

  /// The longest value one notification to this central can carry.
  int get maximumUpdateLength;

  CentralHandle get native;
}

/// A characteristic or descriptor served by this device.
///
/// Without [onRead], reads return the attribute's current value. Without
/// [onWrite], writes replace it. With a handler, the handler decides.
sealed class LocalAttribute {
  LocalAttribute(
    this.uuid, {
    required this.permissions,
    required List<int> value,
    this.onRead,
    this.onWrite,
  }) : value = Uint8List.fromList(value) {
    if (value.length > maxLength) {
      throw ArgumentError.value(value.length, 'value', 'longer than 512 bytes');
    }
  }

  /// The longest attribute value the ATT protocol allows.
  static const maxLength = 512;

  final BluetoothUuid uuid;
  final Set<AttributePermission> permissions;

  /// The initial value.
  final Uint8List value;
  final ReadHandler? onRead;
  final WriteHandler? onWrite;

  bool get isReadable =>
      permissions.contains(AttributePermission.read) ||
      permissions.contains(AttributePermission.readEncrypted);

  bool get isWritable =>
      permissions.contains(AttributePermission.write) ||
      permissions.contains(AttributePermission.writeEncrypted);
}

final class LocalCharacteristic extends LocalAttribute {
  /// Permissions default to what [properties] allow.
  LocalCharacteristic(
    super.uuid, {
    required this.properties,
    Set<AttributePermission>? permissions,
    super.value = const [],
    this.descriptors = const [],
    super.onRead,
    super.onWrite,
  }) : super(permissions: permissions ?? _permissionsFor(properties)) {
    if (descriptors.any(
      (d) => d.uuid == BluetoothUuid.clientCharacteristicConfiguration,
    )) {
      throw ArgumentError(
        'bt_kit manages the Client Characteristic Configuration descriptor',
      );
    }
  }

  final CharacteristicProperties properties;
  final List<LocalDescriptor> descriptors;

  bool get canNotify => properties.notify || properties.indicate;

  static Set<AttributePermission> _permissionsFor(
    CharacteristicProperties properties,
  ) => {
    if (properties.read) AttributePermission.read,
    if (properties.write || properties.writeWithoutResponse)
      AttributePermission.write,
  };

  @override
  String toString() => 'LocalCharacteristic($uuid)';
}

/// A descriptor of a [LocalCharacteristic].
///
/// iOS serves only the User Description and Presentation Format
/// descriptors, with fixed values.
final class LocalDescriptor extends LocalAttribute {
  LocalDescriptor(
    super.uuid, {
    super.permissions = const {AttributePermission.read},
    super.value = const [],
    super.onRead,
    super.onWrite,
  });

  /// Characteristic User Description (`0x2901`).
  LocalDescriptor.userDescription(String description)
    : this(userDescriptionUuid, value: utf8.encode(description));

  /// Characteristic Presentation Format (`0x2904`).
  LocalDescriptor.presentationFormat(List<int> format)
    : this(presentationFormatUuid, value: format);

  static final userDescriptionUuid = BluetoothUuid.short(0x2901);
  static final presentationFormatUuid = BluetoothUuid.short(0x2904);

  @override
  String toString() => 'LocalDescriptor($uuid)';
}

final class LocalService {
  LocalService(
    this.uuid,
    List<LocalCharacteristic> characteristics, {
    this.isPrimary = true,
    List<LocalService> includedServices = const [],
  }) : characteristics = List.unmodifiable(characteristics),
       includedServices = List.unmodifiable(includedServices);

  final BluetoothUuid uuid;
  final List<LocalCharacteristic> characteristics;
  final bool isPrimary;

  /// Services this one includes, such as a secondary service. Add them to
  /// the server first.
  final List<LocalService> includedServices;

  @override
  String toString() => 'LocalService($uuid)';
}

final class ReadRequest {
  const ReadRequest(this.central, this.attribute);

  final Central central;
  final LocalAttribute attribute;
}

final class WriteRequest {
  const WriteRequest(
    this.central,
    this.attribute,
    this.value, {
    required this.withResponse,
  });

  final Central central;
  final LocalAttribute attribute;

  /// The complete new value; prepared (long) writes arrive assembled.
  final Uint8List value;
  final bool withResponse;
}

/// A central subscribed to or unsubscribed from a characteristic.
final class SubscriptionChange {
  const SubscriptionChange(
    this.central,
    this.characteristic, {
    required this.subscribed,
  });

  final Central central;
  final LocalCharacteristic characteristic;
  final bool subscribed;
}
