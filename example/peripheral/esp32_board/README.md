# Hello board firmware

Firmware for the app's **Hello board** demo (More › Hello board): the board's button draws a circle on the phone, the phone's Blink button flashes the board's LED, and the LED shows where the link is. The app's side is in [`../../lib/features/board/`](../../lib/features/board/).

It is separate from the Lab reference firmware in [`../esp32/`](../esp32/); switching a board between the two means flashing it again.

```sh
. ~/.espressif/tools/activate_idf_v6.1.1.sh   # or your ESP-IDF 6.1 export script
cd example/peripheral/esp32_board
idf.py set-target esp32
idf.py -p <serial port> flash monitor
```

It runs on an ESP32-WROOM-32 board as it comes: the BOOT button (GPIO 0) is the button, and the blue LED on GPIO 2 (DevKit V1, NodeMCU-32S) is the LED. Other ESP32 chips work after `idf.py set-target`.

## Settings

`idf.py menuconfig` › *Board demo*:

| Setting | Default | |
|---|---|---|
| LED kind | Single color | Or an RGB LED on three pins, or one WS2812 |
| LED GPIO | 2; 18 for a WS2812 | |
| The LED lights when its pin is low | No | Single color only |
| Red, green, blue GPIO | 25, 26, 27 | RGB only |
| Common anode | No | RGB only |
| Brightness cap | 64 of 255 | The brightest any LED gets |
| Button GPIO | 0 | |
| The button pulls its pin low when pressed | Yes | |

A single-color LED shows every state by its blink pattern; while the button is held, it brightens from 20% to full over 5 seconds. The app's on-screen LED shows the colors.

## What the LED says

| State | Pattern | Color |
|---|---|---|
| Starting | Solid | White |
| Waiting for a phone | Slow blink: 100 ms on, 900 ms off | Blue |
| A phone connected; the app is setting up | Fast blink: 125 ms on, 125 ms off | Amber |
| Ready: the app is subscribed to the button | Solid | Green |
| The phone left | Two quick flashes, then waiting | Red |
| The Bluetooth host reset | Fast blink, then waiting once the host syncs again | Red |

Two overlays draw over the state pattern, and the state pattern comes back when they end. Flashes, sent by the app or the link-lost signal, show the given color 150 ms on and 150 ms off. While the button is held, the LED shows the hue ramp, which the app's circle shares:

```
hue(t) = (120° − 42° × min(t, 5 s) / 1 s) mod 360°
```

`t` is the time the button has been held: the hue starts at green and passes yellow, orange and red to violet at 5 seconds, where it stays.

Colors need an RGB LED or a WS2812. With a single-color LED, *connected* and *host reset* look the same; the serial log tells them apart.

## Bluetooth profile

### Advertising

| Field | Value |
|---|---|
| Type | Legacy, connectable and scannable (`ADV_IND`), interval 20–30 ms |
| Complete list of 128-bit service UUIDs | `f3b1a030-6b2c-4e7a-9a54-7c2d8e0b1a00` |
| Local name (scan response) | `bt_kit Board XXXX`: the last two bytes of the address, as uppercase hex |
| Address | A static random address made from the chip's public address by setting its top two bits (`E4:0A:C4:07:29:6A` for `24:0A:C4:07:29:6A`), or also flipping bit 5 where they are set already |

The board accepts one phone at a time. It stops advertising while connected and starts again within a second after the phone disconnects.

### Service

The UUIDs continue the app's range in `AppUuids` (base `f3b1aXXX-6b2c-4e7a-9a54-7c2d8e0b1a00`): service `030`, characteristics `031` to `034`. No pairing is needed; every characteristic is open.

| ID | Characteristic | Properties | Value |
|---|---|---|---|
| `031` | Button | read, notify | [Button value](#button-value), 7 bytes |
| `032` | LED command | write, write without response | [LED commands](#led-commands) |
| `033` | LED | read, notify | [LED value](#led-value), 6 bytes |
| `034` | Board info | read | Byte 0: LED kind (`00` single color, `01` RGB, `02` addressable), then UTF-8 of at most 63 bytes, such as `esp32 rev0.0 esp-idf v6.1.1 fw 1.0.0` |

Notify characteristics carry a CCCD (`2902`).

### Button value

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | State: `00` released, `01` pressed |
| 1 | 2 | Presses since boot, uint16 little-endian. It goes up by 1 on each press and wraps. |
| 3 | 4 | Hold time in ms, uint32 little-endian. `0` in a press notification; the whole hold in a release notification; the time so far when read during a hold. |

The board sends a notification on each press and each release, after a 30 ms debounce. Example: the release of press 3 after 2,400 ms is `00 03 00 60 09 00 00`.

### LED commands

| Bytes | Command |
|---|---|
| `00` | Stop flashing; the LED goes back to its state pattern |
| `01 rr gg bb nn` | Flash `nn` times (1–10) in color `rrggbb`, 150 ms on, 150 ms off. Replaces a running flash. |

Invalid writes change nothing and fail with an ATT error:

| Write | ATT error |
|---|---|
| Empty; `00` with extra bytes; `01` not followed by exactly 4 bytes | `0x0D` Invalid Attribute Value Length |
| Unknown command, or `nn` of 0 or above 10 | `0x13` Value Not Allowed |

### LED value

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | State: `00` starting, `01` waiting, `02` connected, `03` ready, `04` error |
| 1 | 1 | Pattern shown: `00` off, `01` solid, `02` slow blink, `03` fast blink, `04` hold ramp, `05` flashes |
| 2 | 3 | Color, `rr gg bb`, before the brightness cap. For the hold ramp, the color at the start of the hold. |
| 5 | 1 | Number of flashes for pattern `05`; otherwise `00` |

The board notifies this value when any field changes, and after every accepted flash command, so a flash that restarts with the same color restarts on the screen too. It does not notify while the hold ramp changes color, because the app computes that color itself. The pattern timings in [What the LED says](#what-the-led-says) are part of the contract: the app's on-screen LED copies them.

## Serial log

```
I (783) board: chip address 24:0a:c4:07:29:6a
I (783) board: bt_kit Board 296A e4:0a:c4:07:29:6a
I (803) board: state starting -> waiting
I (22663) board: connection 0 opened
I (22663) board: connection interval 30.00 ms, latency 0, timeout 5000 ms
I (22663) board: state waiting -> connected
I (23623) board: connection interval 15.00 ms, latency 0, timeout 5000 ms
I (23683) board: state connected -> ready
I (37223) board: command: flash ff00ff, count 3
I (76953) board: press 2
I (78753) board: release 2 after 1800 ms
```

The board advertises from a static random address made from the chip's address, so a phone that paired with the Lab firmware on the same chip sees it as a different device. The name ends in the last two bytes of the address, so several boards in one room can be told apart in the app's picker.

## Checking it from a phone

The integration test checks the profile, the LED states and every LED command, including the ATT errors for invalid ones:

```sh
cd example
flutter test integration_test/board_test.dart -d <phone>
```
