import 'dart:async';

import 'package:jni/jni.dart';

import '../../core/log.dart';
import '../../models/audio_connection.dart';
import '../../models/bluetooth_connection_state.dart';
import '../../native/android/bindings.dart';
import '../audio_backend.dart';
import 'android_broadcasts.dart';
import 'android_central.dart';
import 'jni_conversions.dart';

/// Audio profile state through profile proxies and their broadcasts.
///
/// Platform quirks handled here:
/// * Profile proxies arrive asynchronously through a `ServiceListener` and
///   hold a binder connection until closed, so each query opens and closes
///   its own.
/// * A2DP reports playing separately from connecting
///   (`ACTION_PLAYING_STATE_CHANGED`), with its own state constants.
final class AndroidAudio implements AudioBackend {
  AndroidAudio(this._central);

  static const _proxyTimeout = Duration(seconds: 5);

  final AndroidCentral _central;
  late final Stream<AudioConnection> _changes = androidBroadcasts(
    _central.context,
    [for (final action in _actions.keys) action.toJString()],
    _parse,
  );

  /// Broadcast actions and the profile each reports.
  static final _actions = {
    takeString(BluetoothA2dp.ACTION_CONNECTION_STATE_CHANGED)!:
        AudioProfile.a2dp,
    takeString(BluetoothA2dp.ACTION_PLAYING_STATE_CHANGED)!: AudioProfile.a2dp,
    takeString(BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED)!:
        AudioProfile.headset,
    takeString(BluetoothLeAudio.ACTION_LE_AUDIO_CONNECTION_STATE_CHANGED)!:
        AudioProfile.leAudio,
    takeString(BluetoothHearingAid.ACTION_CONNECTION_STATE_CHANGED)!:
        AudioProfile.hearingAid,
  };
  static final _playingAction = takeString(
    BluetoothA2dp.ACTION_PLAYING_STATE_CHANGED,
  );

  @override
  Future<List<AudioConnection>> connections(Set<AudioProfile> profiles) async =>
      [for (final profile in profiles) ...await _connections(profile)];

  @override
  Stream<AudioConnection> get changes => _changes;

  Future<List<AudioConnection>> _connections(AudioProfile profile) async {
    final proxy = await _proxy(profile);
    if (proxy == null) return const [];
    try {
      final devices = guardJni(
        'Listing ${profile.name} devices',
        () => proxy.getConnectedDevices()?.asDart().nonNulls.toList(),
      );
      return [
        for (final device in devices ?? const <BluetoothDevice>[])
          AudioConnection(
            deviceId: takeString(device.address) ?? '',
            deviceName: guardJni(
              'Reading the device name',
              () => takeString(device.name),
            ),
            profile: profile,
            state: BluetoothConnectionState.connected,
            isPlaying:
                profile == AudioProfile.a2dp &&
                proxy.as(BluetoothA2dp.type).isA2dpPlaying(device),
          ),
      ];
    } finally {
      _close(profile, proxy);
    }
  }

  /// The proxy for [profile], or null when the device does not offer it.
  ///
  /// A proxy that does not connect in time counts as unavailable; if it
  /// connects later, it is closed at once.
  Future<BluetoothProfile?> _proxy(AudioProfile profile) {
    if (profile == AudioProfile.leAudio && !_leAudioSupported) {
      return Future.value();
    }
    final proxy = Completer<BluetoothProfile?>();
    final listener = BluetoothProfile$ServiceListener.implement(
      $BluetoothProfile$ServiceListener(
        onServiceConnected: (_, connected) {
          if (!proxy.isCompleted) return proxy.complete(connected);
          if (connected != null) _close(profile, connected);
        },
        onServiceConnected$async: true,
        onServiceDisconnected: (_) {},
        onServiceDisconnected$async: true,
      ),
    );
    final available = guardJni(
      'Opening the ${profile.name} proxy',
      () => _central.adapter.getProfileProxy(
        _central.context,
        listener,
        _profileId(profile),
      ),
    );
    if (!available) return Future.value();
    return proxy.future.timeout(
      _proxyTimeout,
      onTimeout: () {
        BtLog.audio.warning(
          () =>
              'The ${profile.name} profile proxy did not connect; '
              'treating the profile as unavailable',
        );
        proxy.complete(null);
        return null;
      },
    );
  }

  void _close(AudioProfile profile, BluetoothProfile proxy) => guardJni(
    'Closing a profile proxy',
    () => _central.adapter.closeProfileProxy(_profileId(profile), proxy),
  );

  /// Android 13 opens an LE Audio proxy even where the controller has no
  /// LE Audio, and it never connects.
  bool get _leAudioSupported => guardJni(
    'Checking LE Audio support',
    () =>
        _central.adapter.isLeAudioSupported() ==
        BluetoothStatusCodes.FEATURE_SUPPORTED,
  );

  static AudioConnection? _parse(Intent intent) {
    final action = takeString(intent.action);
    final profile = _actions[action];
    final address = addressExtra(intent);
    if (profile == null || address == null) return null;
    final state = intent.getIntExtra(BluetoothProfile.EXTRA_STATE, -1);
    if (action == _playingAction) {
      return AudioConnection(
        deviceId: address,
        profile: profile,
        state: BluetoothConnectionState.connected,
        isPlaying: state == BluetoothA2dp.STATE_PLAYING,
      );
    }
    return AudioConnection(
      deviceId: address,
      profile: profile,
      state: switch (state) {
        BluetoothProfile.STATE_CONNECTED => BluetoothConnectionState.connected,
        BluetoothProfile.STATE_CONNECTING =>
          BluetoothConnectionState.connecting,
        BluetoothProfile.STATE_DISCONNECTING =>
          BluetoothConnectionState.disconnecting,
        _ => BluetoothConnectionState.disconnected,
      },
    );
  }

  static int _profileId(AudioProfile profile) => switch (profile) {
    AudioProfile.a2dp => BluetoothProfile.A2DP,
    AudioProfile.headset => BluetoothProfile.HEADSET,
    AudioProfile.leAudio => BluetoothProfile.LE_AUDIO,
    AudioProfile.hearingAid => BluetoothProfile.HEARING_AID,
  };
}
