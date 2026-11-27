# Bluetooth Radar

The bt_kit example app. It turns the Bluetooth devices around you into something you can see, hear and play with, and it carries bt_kit's on-device test suite, the Lab ([`../doc/testing.md`](../doc/testing.md#lab)).

```sh
cd example
flutter run
```

Bluetooth needs a real phone: Android 13 (API 33) or later, or an iPhone on iOS 18 or later. Simulators and emulators show the onboarding and an empty radar.

## What's inside

| Screen | Where | Shows off |
|---|---|---|
| **Radar** | Home | One shared scan, advertisement parsing, device categories |
| **Device card** | Tap a blip | Parsed advertisement; **Hunt** and **Connect** |
| **Hunt** | Device card | High-rate scanning on the shared scan, RSSI smoothing, clicks and vibration |
| **Party** | Hunt › Start a party; More › Join a party | GATT server, advertising, notifications between phones |
| **GATT explorer** | Device card › Connect | Connect, discover, read, write, subscribe, Layer 1 through `native` |
| **Heart-rate showdown** | Showdown tab | Several connections, notifications, reconnects |
| **Beacon mode** | More | Advertising, so a phone can be a Hunt target |
| **File beam** | More | GATT server, L2CAP channels, throughput |
| **Hello board** | More | An ESP32's button and LED, live: notifications, writes, reconnects ([firmware](peripheral/esp32_board/)) |
| **Things that stayed with you** | More (experiment) | Long-running scan analysis |
| **Share card** | Radar › Share | An image of the radar, without device ids |
| **Lab** | Long-press the Radar title | On-device tests: GATT flows, connection cycles, a notification soak, cancellation and timeouts, scan load, filters and link features (MTU, PHY, priority, Services Changed, disconnect reasons) and platform features (bonding, background scans, connection events, distance, audio state, Classic discovery) |

Every screen has a `</>` button that shows the bt_kit call behind it, and the Layer 1 calls bt_kit makes on Android and iOS.

## Structure

```
lib/
├── main.dart
├── app/            Theme, navigation, onboarding, system settings
├── bluetooth/      App logic on top of bt_kit: the shared scan, category rules,
│                   RSSI filter, heart-rate parser
├── features/       One folder per screen
└── widgets/        Radar painter, code sheet, shared UI
test/               Parsers, filters, category rules, protocols; fakes/ runs
                    screens on bt_kit's FakeBluetooth
integration_test/   Lab flows and Layer 1 smoke tests
peripheral/         The Lab reference peripheral profile and its ESP32 firmware;
                    esp32_board/ is the Hello board firmware
```

State lives in `ChangeNotifier`s, with no state management package. The only packages beyond bt_kit are `share_plus` and `audioplayers`.

## Rules the app follows

- **One scan.** [`Scanner`](lib/bluetooth/scanner.dart) runs one long scan (`allowDuplicates: true`, `ScanMode.lowLatency`) while the app is visible. `BtKit.scanDevices` decides which devices are around and when screens redraw; every advertisement still updates its device, to smooth the signal strength. Screens filter it in Dart; screens that need every advertisement call `BtKit.instance.scan(Scanner.options)`, which shares the same native scan. The Lab pauses it to scan with filters of its own.
- **Honest numbers.** Signal strength gives *near*, *around* and *far*, never meters.
- **Privacy.** No accounts, uploads or location; nothing is stored after the app closes.

## Tests

```sh
flutter test                                                # host and widget tests
flutter test integration_test/layer1_smoke_test.dart -d <phone>
flutter test integration_test/lab_test.dart -d <phone>      # quick Lab suite
flutter test integration_test/board_test.dart -d <phone>    # a Hello board nearby
flutter test integration_test/lab_test.dart -d <phone> \
    --dart-define=LAB_FULL=true --dart-define=LAB_PAIRING=true
```

The Lab and its integration tests need a reference peripheral: a second phone with the Lab open on **Be the reference**, or firmware that implements [`peripheral/README.md`](peripheral/README.md). Headless Android runs need the permissions granted first; see [Running the suites](peripheral/README.md#running-the-suites).

Two Android emulators on the same computer share a virtual Bluetooth radio, which is enough for the Radar, beacon mode, the GATT explorer and the Lab, but not for radio behavior such as signal strength.
