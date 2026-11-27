/// What the platform and the local adapter support.
///
/// Check these before calling an API that may be unavailable; the call
/// otherwise fails with `UnsupportedFeatureException`.
final class BluetoothCapabilities {
  const BluetoothCapabilities({
    required this.lowEnergy,
    required this.classic,
    required this.le2MPhy,
    required this.leCodedPhy,
    required this.extendedAdvertising,
    required this.periodicAdvertising,
    required this.channelSounding,
    required this.requestMtu,
    required this.connectionPriority,
    required this.phy,
    required this.notifyMode,
    required this.requestEnable,
    required this.peripheralRole,
    required this.advertiseLocalName,
    required this.advertiseCustomData,
    required this.l2cap,
    required this.bonding,
    required this.removeBond,
    required this.externalAccessory,
    required this.companionDevices,
    required this.backgroundEvents,
    required this.stateRestoration,
    required this.systemConnectionEvents,
    required this.rssiRanging,
    required this.audioProfiles,
    required this.gattCacheRefresh,
    required this.adapterName,
    required this.serverConnectionPriority,
  });

  /// Bluetooth Low Energy.
  final bool lowEnergy;

  /// Bluetooth Classic (BR/EDR). iOS only reaches Classic accessories
  /// through ExternalAccessory, which Layer 1 exposes.
  final bool classic;

  final bool le2MPhy;
  final bool leCodedPhy;
  final bool extendedAdvertising;

  /// Periodic advertising, through `AdvertiseOptions.periodic` (Android).
  final bool periodicAdvertising;

  /// Bluetooth 6.0 Channel Sounding.
  final bool channelSounding;

  /// The app can request an ATT MTU. iOS negotiates it automatically.
  final bool requestMtu;

  /// The app can request a connection priority (Android).
  final bool connectionPriority;

  /// The app can read and choose a connection's PHY (Android). Which PHYs
  /// the adapter offers is in [le2MPhy] and [leCodedPhy].
  final bool phy;

  /// The app can choose between notification and indication when a
  /// characteristic supports both (Android).
  final bool notifyMode;

  /// The app can ask the user to turn Bluetooth on (Android).
  final bool requestEnable;

  /// The device can advertise and run a GATT server.
  final bool peripheralRole;

  /// Advertisements can carry a custom local name (iOS).
  final bool advertiseLocalName;

  /// Advertisements can carry manufacturer data, service data and the
  /// transmit power (Android).
  final bool advertiseCustomData;

  /// L2CAP connection-oriented channels.
  final bool l2cap;

  /// The app can start pairing and list bonded devices (Android). iOS pairs
  /// on its own when the app first uses an encrypted attribute.
  final bool bonding;

  /// The app can remove a bond itself (Android 16, API 36, and later,
  /// through a companion device association). Elsewhere `removeBond` opens
  /// the Bluetooth settings for the user instead.
  final bool removeBond;

  /// MFi accessories over ExternalAccessory (iOS).
  final bool externalAccessory;

  /// The system companion device picker: `CompanionDeviceManager` on
  /// Android, AccessorySetupKit on iOS.
  final bool companionDevices;

  /// Events that reach the app while it is not running: background scans
  /// and companion device presence (Android).
  final bool backgroundEvents;

  /// The system relaunches the app for Bluetooth events and restores its
  /// managers (iOS).
  final bool stateRestoration;

  /// Events for connections that any app opens.
  final bool systemConnectionEvents;

  /// Distance estimates from signal strength (Android 16, API 36, and
  /// later). Channel Sounding is [channelSounding].
  final bool rssiRanging;

  /// The connection state of audio profiles such as A2DP and LE Audio
  /// (Android).
  final bool audioProfiles;

  /// The app can clear the cached GATT database of a peripheral (Android,
  /// through a non-SDK interface).
  final bool gattCacheRefresh;

  /// The app can read the name the adapter shows to other devices
  /// (Android).
  final bool adapterName;

  /// A GATT server can ask a connected central for a connection priority
  /// (iOS).
  final bool serverConnectionPriority;
}
