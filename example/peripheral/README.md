# Lab reference peripheral

The Lab (long-press the Radar title) runs bt_kit's on-device tests ([`../../doc/testing.md`](../../doc/testing.md#lab)) against a peripheral that serves this GATT profile. Two things can serve it:

- **A second phone** running the Lab's **Be the reference** tab ([`lib/features/lab/peripheral/`](../lib/features/lab/peripheral/)). This needs no extra hardware, and it validates bt_kit's peripheral role at the same time.
- **Reference firmware** for an ESP32 in [`esp32/`](esp32/), which takes the phone's peripheral role out of the measurement. This page is its specification.

The Dart definition is [`lib/features/lab/profile/`](../lib/features/lab/profile/). Its unit tests in [`test/lab/`](../test/lab/) check the encodings below.

## Advertising

| Field | Value |
|---|---|
| Type | Legacy, connectable and scannable (`ADV_IND`) |
| Complete list of 128-bit service UUIDs (AD type `0x07`) | `f3b1a100-6b2c-4e7a-9a54-7c2d8e0b1a00` |
| Manufacturer data (AD type `0xFF`) | Company `0xFFFF` (reserved by the Bluetooth SIG for tests), then `4c`: `ff ff 4c`. Android phones send it; iOS cannot. |
| Local name (scan response) | `bt_kit Lab`. An Android phone advertises its Bluetooth name instead. |
| Service data (scan response, AD type `0x21`) | The 128-bit service UUID, then `4c`. Firmware only: phones have no room for it. With the name, the scan response is exactly 31 bytes. |
| Interval | 20–100 ms |

The Lab finds references by the service UUID alone; its *Filters and link features* test also finds them by name, by manufacturer data and by service data, and skips the filters for fields a reference does not send. Keep advertising while a central is connected, and resume within a second after it disconnects: the connection test reconnects about every two seconds, 500 times. Firmware should use a static address; phones rotate theirs about every 15 minutes, and the Lab finds them again by the service UUID.

## Service

All UUIDs share the base `f3b1aXXX-6b2c-4e7a-9a54-7c2d8e0b1a00`. In the little-endian byte order used over the air and by most stacks, the service is:

```
00 1a 0b 8e 2d 7c 54 9a 7a 4e 2c 6b 00 a1 b1 f3
```

and each characteristic differs only in the 13th byte (`01` to `0b`). In Zephyr: `BT_UUID_128_ENCODE(0xf3b1a100, 0x6b2c, 0x4e7a, 0x9a54, 0x7c2d8e0b1a00)`.

| ID | Characteristic | Properties | Permissions | Value |
|---|---|---|---|---|
| `101` | Fixed value | read | read | ASCII `bt_kit lab v1` (13 bytes) |
| `102` | Echo | read, write, write without response | read, write | The last value written, up to 512 bytes; empty at start |
| `103` | Notify stream | notify | (CCCD only) | [Stream packets](#stream-packets) |
| `104` | Indicate stream | indicate | (CCCD only) | [Stream packets](#stream-packets) |
| `105` | Long value | read | read | 512 bytes; byte `i` is `i % 251` |
| `106` | Encrypted value | read | read, encryption required | ASCII `encrypted ok` (12 bytes) |
| `107` | Fault control | read, write | read, write | 1 byte: an ATT error code, or `00`; see [Faults](#faults) |
| `108` | Fault target | read | read | ASCII `no fault` (8 bytes), unless a fault is set |
| `109` | Stream control | read, write | read, write | [Stream commands](#stream-commands) |
| `10a` | Info | read | read | UTF-8, at most 64 bytes: who serves the profile |
| `10b` | Database control | read, write | read, write | 1 byte: `01` while the [extra service](#database-changes) is served, otherwise `00` |

Notify and indicate characteristics carry a Client Characteristic Configuration descriptor (`2902`). No other descriptors are required.

### Included service

The service includes a secondary service, `f3b1a120-…`, with one readable characteristic, `f3b1a121-…`, whose value is ASCII `included` (8 bytes). Add it before the Lab service.

The long value has a 251-byte period, a prime, so a blob read at a wrong offset never matches. It needs Read Blob requests at any MTU below 515, and the echo needs Prepare and Execute Write requests for values longer than MTU − 3.

### Info

A short description of the serving device, which the Lab records in its report, such as `nrf52840 zephyr 4.1 fw 1.0.0`, `Android 16 (API 36) Google Pixel 9` or `iOS 26.1.0`.

## Stream packets

Both streams send 12-byte values:

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | Sequence number, uint32 little-endian. `0` for the first packet after each start command, then `+1` per packet. |
| 4 | 8 | Microseconds since the start command, uint64 little-endian, taken when the packet is sent. |

Example: sequence 1 at 20,000 µs is `01 00 00 00 20 4e 00 00 00 00 00 00`.

Packet `n` is due `n / rate` seconds after the start. When sending falls behind, the next packets go out at once until the stream catches up; never skip a sequence number. With indications, send the next packet after the confirmation.

## Stream commands

Writes to the stream control characteristic, with response:

| Bytes | Command |
|---|---|
| `00` | Stop both streams |
| `01 rr rr` | Start the notify stream at `rrrr` packets per second (uint16 little-endian, 1–1000) |
| `02 rr rr` | Start the indicate stream at `rrrr` packets per second |

A start restarts the sequence at `0` and replaces any running stream. Start sending once the writing central has subscribed (wait up to 2 s for its CCCD write). Stop streaming when the last central disconnects. Reads return the last accepted command.

Invalid writes are rejected with an ATT error and change nothing:

| Write | ATT error |
|---|---|
| Empty; `00` with extra bytes; `01` or `02` not followed by exactly 2 bytes | `0x0D` Invalid Attribute Value Length |
| Unknown command, or a rate of 0 or above 1000 | `0x13` Value Not Allowed |

## Faults

Writing an ATT error code to fault control makes every later read of the fault target fail with that error; writing `00` clears it. Reads of fault control return the current code.

| Write | Result |
|---|---|
| `00` | Clear the fault |
| `01` – `13` | Fail fault target reads with this ATT error |
| Any other byte | Rejected with `0x13` Value Not Allowed |
| Not exactly 1 byte | Rejected with `0x0D` Invalid Attribute Value Length |

The Lab uses `02` (Read Not Permitted). Codes `05` (Insufficient Authentication), `0C` and `0F` (encryption) make Android and iOS start pairing instead of reporting the error.

## Database changes

Writing `01` to database control adds a second primary service, `f3b1a110-…`, with one readable characteristic, `f3b1a111-…`, whose value is ASCII `extra` (5 bytes). Writing `00` removes it. Answer the write first, then change the database within a second, so the Service Changed indication follows the write response. Writing the current state changes nothing; any other byte is rejected with `0x13`, and a value that is not 1 byte with `0x0D`.

The Lab adds the service, rediscovers it, reads it, removes it, and checks that the read of the removed characteristic fails. Serve the Service Changed characteristic (`2A05`) in the GATT service and indicate it after each change.

## What the Lab does with it

| Test | Characteristics | Quick | Full |
|---|---|---|---|
| GATT flows | All, once: write with and without response, a 300-byte long write, the long read, 20 notifications at 20 Hz, 10 indications at 10 Hz, a fault, RSSI, MTU; the encrypted read when pairing is included | same | same |
| Connection cycles | Connect, discover, read fixed value, write and read back echo, disconnect | 50 cycles | 500 cycles, ≥ 99.5% succeed |
| Notification soak | Notify stream at 50 Hz | 1 minute | 10 minutes, no lost or out-of-order values |
| Cancellation and timeouts | Fixed value, long value, echo, RSSI in bursts of 20 queued operations, cancelled at random or with 1–30 ms timeouts | 10 bursts | 50 bursts; the queue never stalls and requests never overlap |
| Scan load | None (scanning only) | 2,000 results | 10,000 results, flat memory |
| Filters and link features | Advertising, fixed value, echo, indicate stream, database control and the extra service | same | same |
| More features | Advertising, echo (a 512-byte chunked write), the included service, a GATT cache refresh | same | same |

Firmware requirements that follow from these numbers:

- Accept a new connection immediately after a disconnection, for 500 cycles in a row.
- Sustain 50 notifications per second to one central for 10 minutes at a 7.5–50 ms connection interval and an MTU of 23.
- Answer reads within a few milliseconds; the cancellation test measures the central's queue, not the peripheral.
- Pair with Just Works for the encrypted value; bonding is optional.
- Serve one central at a time; a second central's stream command restarts the stream for both.

## ESP32 firmware

[`esp32/`](esp32/) serves this profile with ESP-IDF 6.1 and NimBLE. (The firmware in [`esp32_board/`](esp32_board/) is a different one, for the app's Hello board demo.) It has been built and run on the original ESP32 (ESP32-D0WDQ6), which has Bluetooth 4.2: LE 1M only, and no extended or periodic advertising.

```sh
cd example/peripheral/esp32
idf.py set-target esp32
idf.py -p <serial port> flash monitor
```

- It advertises from the chip's public address, so its id never changes.
- Bonds persist in NVS, up to 8, and the oldest is replaced when the store is full. A central that pairs again after losing its keys replaces its old bond. `idf.py -p <serial port> erase-flash` clears every bond.
- Up to 3 centrals can connect at once; it keeps advertising until all 3 are connected.
- Its Info value reads like `esp32 rev0.0 esp-idf v6.1.1 nimble fw 1.0.0`.
- The serial console logs connections, MTU changes, encryption, streams and database changes.

## Running the suites

On the phone under test, open the Lab, pick the reference and run the tests, or run them headless:

```sh
flutter test integration_test/lab_test.dart -d <phone>
flutter test integration_test/lab_test.dart -d <phone> \
    --dart-define=LAB_FULL=true --dart-define=LAB_PAIRING=true
```

On Android, grant the permissions first to run unattended (`RANGING` is for the Distance step on Android 16 and later):

```sh
for p in BLUETOOTH_SCAN BLUETOOTH_CONNECT BLUETOOTH_ADVERTISE RANGING; do
  adb shell pm grant dev.btkit.bt_radar android.permission.$p
done
```

The Lab shares its results as JSON (schema `bt_kit.lab/1`) with the device, the reference's Info value, each test's criteria, checks and metrics. JNI global references cannot be read from inside the app: for the scan load on Android, compare `adb shell dumpsys meminfo dev.btkit.bt_radar` before and after, and fill in `metrics.jniGlobalReferences` in the report.
