/// Bluetooth for Flutter on Android and iOS.
///
/// This library is Layer 2, the unified API: Futures, Streams and Dart
/// models with per-connection queues, timeouts, cancellation and a sealed
/// [BluetoothException] hierarchy. It covers the central role ([BtKit.scan],
/// [Peripheral]), the peripheral role ([GattServer], [AdvertisingSession]),
/// L2CAP channels ([L2capChannel], [L2capServer]), bonding, Bluetooth
/// Classic ([ClassicBluetooth]), MFi accessories ([ExternalAccessories]),
/// companion devices ([CompanionDevices]), background delivery
/// ([BackgroundEvent]), state restoration ([RestoredState]), distance
/// measurement ([Peripheral.measureDistance]) and audio profile state
/// ([AudioProfiles]).
///
/// Every object exposes the Layer 1 object behind it through `native`. For
/// the full platform APIs, import `package:bt_kit/android.dart` or
/// `package:bt_kit/ios.dart`; both layers can be used together.
library;

export 'package:logging/logging.dart' show Level;

export 'src/accessories/external_accessories.dart'
    hide createExternalAccessories;
export 'src/audio/audio_profiles.dart' hide createAudioProfiles;
export 'src/background/background_event.dart';
export 'src/central/advertisement.dart';
export 'src/central/bt_kit.dart' hide installBackend;
export 'src/central/native_types.dart';
export 'src/central/peripheral.dart' hide createPeripheral;
export 'src/central/peripheral_event.dart';
export 'src/central/restored_state.dart';
export 'src/channels/byte_channel.dart'
    hide
        createAccessorySession,
        createL2capChannel,
        createL2capServer,
        createRfcommChannel,
        createRfcommServer;
export 'src/classic/classic_bluetooth.dart' hide createClassicBluetooth;
export 'src/companion/companion_devices.dart' hide createCompanionDevices;
export 'src/core/bluetooth_uuid.dart';
export 'src/core/cancel_token.dart';
export 'src/core/exceptions.dart';
export 'src/core/native_handle.dart';
export 'src/models/adapter_state.dart';
export 'src/models/advertise_options.dart';
export 'src/models/advertisement_data.dart';
export 'src/models/advertisement_filter.dart';
export 'src/models/attribute_permission.dart';
export 'src/models/audio_connection.dart';
export 'src/models/bond_state.dart';
export 'src/models/bt_kit_options.dart';
export 'src/models/capabilities.dart';
export 'src/models/characteristic_properties.dart';
export 'src/models/companion_request.dart';
export 'src/models/connection_priority.dart';
export 'src/models/bluetooth_connection_state.dart';
export 'src/models/device_class.dart';
export 'src/models/disconnect_reason.dart';
export 'src/models/distance.dart';
export 'src/models/notify_mode.dart';
export 'src/models/permission.dart';
export 'src/models/phy.dart';
export 'src/models/scan_options.dart';
export 'src/models/system_connection.dart';
export 'src/peripheral_role/advertising_session.dart'
    hide checkAdvertising, createAdvertisingSession;
export 'src/peripheral_role/gatt_server.dart' hide createGattServer;
export 'src/peripheral_role/local_gatt.dart';
