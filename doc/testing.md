# Testing

| Suite | Runs on | Covers |
|---|---|---|
| Unit | Host (`flutter test`) | Pure Dart logic, and Layer 2 policy against fake backends |
| Generator checks | Host, with the platform SDKs | Generated bindings match the SDKs and the exposure rules |
| Integration | Phone (`example/integration_test`) | Layer 1, and both layers together, against the platform's Bluetooth stack |
| Lab | Phone and a reference peripheral | GATT flows, endurance, cancellation and platform features over a real radio |

## Unit tests

Layer 2 keeps all policy in platform-neutral code above the backends (see [architecture.md](architecture.md#layer-2)), so the unit tests run it against fake backends with no radio.

- `core/`: `BluetoothUuid` parsing and formatting; `OperationQueue` ordering, timeouts, cancellation, holding the queue until the platform answers, and draining; logging, which is off by default, gated by `BtKit.logLevel`, and records a timed-out operation with its time in the queue and the native status of the late answer.
- `models/`: advertisement parsing for every AD type Layer 2 reads, including malformed input; advertisement filters, AND within a filter and OR across filters, with masks; scan options and their sharing rules; the Class of Device fields.
- `platform/`: `RequestSlot` matching, late callbacks, superseded requests, and a request that fails only itself; what each platform filters natively; the native disconnect-status mappings.
- `central/`:
  - Shared scan sessions, conflicting options, timeouts, filtering before de-duplication, and scan state.
  - The device list's expiry and throttling on a fake clock.
  - `Peripheral` and `BtKit` end to end on `FakeBluetooth`: values, subscriptions and notify modes, Services Changed, MTU, priority, PHY, disconnect reasons, app connections and events, permission and adapter failures, and scripted errors and timeouts.
  - Chunked writes and their held queue, connecting with an MTU, included services, GATT cache refresh and the adapter name.
  - Bonding: pairing and its events, joining a pairing in progress, rejection, timed-out and cancelled pairing, and removal with and without `capabilities.removeBond`.
  - Background scan results and companion presence as `BackgroundEvent`s, restoration replay, `configure` ordering, system connections, audio state and distance measurement.
- `peripheral_role/`: `GattServer` against a fake backend.
  - Reads: stored values, handlers, long-read snapshots, ATT errors and handler timeouts.
  - Writes: offsets, rejection, and all-or-nothing prepared writes.
  - Subscriptions, disconnect cleanup, notification targeting, length limits and per-central ordering.
  - Advertising updates and periodic advertising validation.
- `l2cap/`: write ordering, remote close, and a timed-out write that holds the channel until it finishes.
- `classic/`, `accessories/`, `companion/`: one inquiry at a time, RFCOMM channels and servers, accessory sessions per protocol, and the companion picker's answer, dismissal, associations and presence.
- `layers_test.dart`: Layer 2 and Layer 1 export disjoint names, Layer 1 does not shadow `dart:core`, and interop plumbing stays hidden.

`package:bt_kit/testing.dart` is the same fake stack apps use. A `FakePeripheral` is served by a real `GattServer` over a fake server backend, so fakes and the peripheral role share one implementation of reads, writes, long values and subscriptions. The example app runs its screens on it in `example/test/fakes/`.

## Generator checks

Regenerating Layer 1 must reproduce the checked-in bindings exactly, and the generated Java and Objective-C must compile cleanly. The commands are in [CONTRIBUTING.md](../CONTRIBUTING.md#layer-1-bindings). After an SDK update, the diff of [`doc/inventory/`](inventory/) shows exactly which APIs were added, deprecated or omitted.

## Integration tests

In `example/integration_test/`, run on a phone:

- **Layer 1 smoke** (`layer1_smoke_test.dart`): create a `BluetoothManager` or `CBCentralManager`, read the adapter state, implement the callback classes and delegates, scan, advertise, serve a service and connect to the reference through Layer 1 alone, and check `NoSuchMethodError` and `OsVersionError` for APIs newer than the OS.
- **Mixed layers**: Layer 1 objects reached through `native`, and Layer 1 calls inside `Peripheral.exclusive`.
- **Lab** (`lab_test.dart`): every Lab test below, in its quick or full plan.
- **Hello board** (`board_test.dart`): the board firmware's profile, LED states and commands, including the ATT errors for invalid ones.

## Lab

The example app's Lab (long-press the Radar title) runs against a reference peripheral: a second phone serving the profile from the Lab's **Be the reference** tab, or the ESP32 firmware in [`example/peripheral/esp32/`](../example/peripheral/esp32/). The profile is specified in [`example/peripheral/README.md`](../example/peripheral/README.md).

| Test | Pass criterion (full plan) |
|---|---|
| GATT flows | Every characteristic of the reference behaves as specified: writes with and without response, long reads and writes, notifications, indications, ATT errors, RSSI and MTU |
| Connection cycles | 500 connect, discover, read, write and disconnect cycles; at least 99.5% succeed |
| Notification soak | 50 Hz for 10 minutes; no lost or out-of-order values |
| Cancellation and timeouts | 50 bursts of 20 operations with random cancellations and 1–30 ms timeouts; the queue never stalls and requests never overlap |
| Scan load | 10,000 scan results; process memory grows less than 5 MiB after warm-up |
| Filters and link features | Each scan filter finds the reference; last values, explicit indications, MTU state, connection priority, PHY, Services Changed and disconnect reasons |
| Platform features | Bonding, background scans, connection events, distance, audio state and Classic discovery, where the platform offers them |
| More features | Scan settings, connecting with an MTU, chunked writes, included services, GATT cache refresh, the adapter name, advertising updates and periodic advertising, where the platform offers them |

The quick plan runs the same tests shorter: 50 cycles, a 1-minute soak, 10 bursts and 2,000 scan results. [`example/README.md`](../example/README.md#tests) has the commands.
