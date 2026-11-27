import 'dart:async';

import 'package:bt_kit/bt_kit.dart';
import 'package:flutter/foundation.dart';

import '../../../bluetooth/app_uuids.dart';
import '../protocol/beam_link.dart';
import 'beam_problem.dart';
import 'beam_reception.dart';

enum ReceiverSetup { starting, ready, failed }

/// Makes this phone a File beam receiver: it publishes an L2CAP channel,
/// serves the channel's PSM from a GATT server and advertises the service.
final class BeamReceiver extends ChangeNotifier {
  BeamReceiver([BtKit? bt]) : _bt = bt ?? BtKit.instance;

  /// The name an iPhone advertises; Android cannot set one.
  static const localName = 'Beam';
  static const _refresh = Duration(milliseconds: 200);

  /// iOS runs one GATT server and one advertisement per app, so a new
  /// receiver waits until the previous one has let go of them.
  static var _previousRelease = Future<void>.value();

  final BtKit _bt;
  var _setup = ReceiverSetup.starting;
  BeamProblem? _setupProblem;
  BeamReception? _reception;
  L2capServer? _l2cap;
  StreamSubscription<L2capChannel>? _channels;
  GattServer? _gatt;
  AdvertisingSession? _advertising;
  Timer? _ticker;
  var _disposed = false;

  ReceiverSetup get setup => _setup;

  BeamProblem? get setupProblem => _setupProblem;

  /// The latest transfer, running or finished.
  BeamReception? get reception => _reception;

  bool get advertisesName => _bt.capabilities.advertiseLocalName;

  Future<void> start() async {
    _setSetup(ReceiverSetup.starting);
    BeamProblem? problem;
    try {
      await _previousRelease;
      problem = await _open();
    } on Object catch (error) {
      problem = BeamProblem.of(error);
    }
    if (_disposed || problem != null) await (_previousRelease = _release());
    _setupProblem = problem;
    _setSetup(problem == null ? ReceiverSetup.ready : ReceiverSetup.failed);
  }

  /// Returns why this phone cannot receive, or null once it is ready.
  Future<BeamProblem?> _open() async {
    final statuses = await _bt.requestPermissions(BtKit.peripheralPermissions);
    if (!statuses.values.every((status) => status.isGranted)) {
      return BeamProblem.permission;
    }
    final capabilities = _bt.capabilities;
    if (!capabilities.peripheralRole || !capabilities.l2cap) {
      return BeamProblem.unsupported;
    }
    final l2cap = _l2cap = await _bt.publishL2capChannel(
      secure: BeamLink.secure,
    );
    _channels = l2cap.channels.listen(_accept);
    _gatt = await _bt.openGattServer(services: [_service(l2cap.psm)]);
    _advertising = await _bt.startAdvertising(
      AdvertiseOptions(
        serviceUuids: [AppUuids.fileBeam],
        localName: capabilities.advertiseLocalName ? localName : null,
      ),
    );
    return null;
  }

  static LocalService _service(int psm) => LocalService(AppUuids.fileBeam, [
    LocalCharacteristic(
      AppUuids.fileBeamPsm,
      properties: const CharacteristicProperties.of(read: true),
      value: BeamLink.encodePsm(psm),
    ),
  ]);

  /// Takes one transfer at a time; a second sender is turned away.
  void _accept(L2capChannel channel) {
    final current = _reception;
    if (current != null && current.isActive) {
      unawaited(channel.close());
      return;
    }
    if (current != null) unawaited(current.close());
    _reception = BeamReception(channel, _onReceptionChange);
    _notify();
  }

  void _onReceptionChange() {
    final receiving = _reception?.stage == ReceptionStage.receiving;
    if (receiving) {
      _ticker ??= Timer.periodic(_refresh, (_) => _notify());
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
    _notify();
  }

  void _setSetup(ReceiverSetup setup) {
    _setup = setup;
    if (setup != ReceiverSetup.failed) _setupProblem = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Stops advertising, then closes the GATT server, the transfer and the
  /// L2CAP server. Each step runs even if an earlier one fails.
  Future<void> _release() async {
    final steps = <Future<void> Function()?>[
      _advertising?.stop,
      _gatt?.close,
      _channels?.cancel,
      _reception?.close,
      _l2cap?.close,
    ];
    _advertising = null;
    _gatt = null;
    _channels = null;
    _l2cap = null;
    for (final step in steps) {
      try {
        await step?.call();
      } on Object catch (_) {}
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _previousRelease = _release();
    super.dispose();
  }
}
