import '../core/bluetooth_uuid.dart';
import '../core/exceptions.dart';
import '../models/audio_connection.dart';
import '../models/bond_state.dart';
import '../models/companion_request.dart';
import '../models/scan_options.dart';
import 'accessory_backend.dart';
import 'audio_backend.dart';
import 'background_backend.dart';
import 'bond_backend.dart';
import 'channel_backend.dart';
import 'classic_backend.dart';
import 'companion_backend.dart';

final class UnsupportedBond implements BondBackend {
  const UnsupportedBond(this._reason);

  final String _reason;

  @override
  BondState get bondState => BondState.none;

  @override
  Stream<BondState> get bondStates => const Stream.empty();

  @override
  Future<void> createBond() => _fail();

  @override
  void cancelBond() {}

  @override
  Future<void> removeBond() => _fail();

  Future<Never> _fail() =>
      Future.error(UnsupportedFeatureException('bonding', _reason));
}

final class UnsupportedClassic implements ClassicBackend {
  const UnsupportedClassic(this._reason);

  final String _reason;

  @override
  Stream<ClassicHit> discover() => Stream.error(_error);

  @override
  Future<ClassicDeviceBackend?> device(String id) => Future.error(_error);

  @override
  Future<List<ClassicDeviceBackend>> bondedDevices() => Future.error(_error);

  @override
  Future<RfcommServerBackend> listen(
    String name,
    BluetoothUuid service, {
    required bool secure,
  }) => Future.error(_error);

  UnsupportedFeatureException get _error =>
      UnsupportedFeatureException('classic', _reason);
}

final class UnsupportedAccessories implements AccessoryBackend {
  const UnsupportedAccessories(this._reason);

  final String _reason;

  @override
  List<AccessoryBackendItem> get connected => const [];

  @override
  Stream<({AccessoryBackendItem accessory, bool connected})> get changes =>
      const Stream.empty();

  @override
  Future<void> showBluetoothPicker() =>
      Future.error(UnsupportedFeatureException('externalAccessory', _reason));
}

final class UnsupportedCompanion implements CompanionBackend {
  const UnsupportedCompanion(this._reason);

  final String _reason;

  @override
  Future<CompanionDeviceBackend?> associate(CompanionRequest request) =>
      Future.error(_error);

  @override
  Future<List<CompanionDeviceBackend>> devices() async => const [];

  @override
  Future<void> remove(CompanionDeviceBackend device) => Future.error(_error);

  @override
  Stream<CompanionChange> get changes => const Stream.empty();

  @override
  Future<void> observePresence(
    CompanionDeviceBackend device, {
    required bool observe,
  }) => Future.error(_error);

  UnsupportedFeatureException get _error =>
      UnsupportedFeatureException('companionDevices', _reason);
}

final class UnsupportedBackground implements BackgroundBackend {
  const UnsupportedBackground(this._reason);

  final String _reason;

  @override
  Future<void> startScan(ScanOptions options) => Future.error(_error);

  @override
  Future<void> stopScan() async {}

  @override
  Stream<BackgroundSignal> get signals => const Stream.empty();

  @override
  void register(int dispatcherHandle, int handlerHandle) => throw _error;

  @override
  int? get handlerHandle => null;

  @override
  void acknowledgeEvents() {}

  @override
  void handled() {}

  UnsupportedFeatureException get _error =>
      UnsupportedFeatureException('backgroundEvents', _reason);
}

final class UnsupportedAudio implements AudioBackend {
  const UnsupportedAudio(this._reason);

  final String _reason;

  @override
  Future<List<AudioConnection>> connections(Set<AudioProfile> profiles) =>
      Future.error(UnsupportedFeatureException('audioProfiles', _reason));

  @override
  Stream<AudioConnection> get changes => const Stream.empty();
}
