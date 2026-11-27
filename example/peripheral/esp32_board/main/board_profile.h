#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "host/ble_uuid.h"

#define BOARD_UUID_BYTES(id)                                                   \
    0x00, 0x1a, 0x0b, 0x8e, 0x2d, 0x7c, 0x54, 0x9a, 0x7a, 0x4e, 0x2c, 0x6b,    \
        ((id) & 0xff), (0xa0 | ((id) >> 8)), 0xb1, 0xf3

#define BOARD_UUID_INIT(id) BLE_UUID128_INIT(BOARD_UUID_BYTES(id))
#define BOARD_UUID_DECLARE(id) BLE_UUID128_DECLARE(BOARD_UUID_BYTES(id))

#define BOARD_SERVICE_ID 0x030
#define BOARD_BUTTON_ID 0x031
#define BOARD_LED_COMMAND_ID 0x032
#define BOARD_LED_ID 0x033
#define BOARD_INFO_ID 0x034

#define BOARD_NAME_PREFIX "bt_kit Board "
#define BOARD_BUTTON_VALUE_LENGTH 7
#define BOARD_LED_VALUE_LENGTH 6
#define BOARD_MAX_INFO_TEXT_LENGTH 63
#define BOARD_MAX_FLASHES 10

typedef enum {
    BOARD_STATE_STARTING = 0x00,
    BOARD_STATE_WAITING = 0x01,
    BOARD_STATE_CONNECTED = 0x02,
    BOARD_STATE_READY = 0x03,
    BOARD_STATE_ERROR = 0x04,
    BOARD_STATES,
} board_state_t;

typedef enum {
    BOARD_PATTERN_OFF = 0x00,
    BOARD_PATTERN_SOLID = 0x01,
    BOARD_PATTERN_SLOW_BLINK = 0x02,
    BOARD_PATTERN_FAST_BLINK = 0x03,
    BOARD_PATTERN_HOLD_RAMP = 0x04,
    BOARD_PATTERN_FLASHES = 0x05,
} board_pattern_t;

typedef enum {
    BOARD_LED_SINGLE = 0x00,
    BOARD_LED_RGB = 0x01,
    BOARD_LED_ADDRESSABLE = 0x02,
} board_led_kind_t;

typedef enum {
    BOARD_COMMAND_STOP = 0x00,
    BOARD_COMMAND_FLASH = 0x01,
} board_command_kind_t;

typedef struct {
    uint8_t red;
    uint8_t green;
    uint8_t blue;
} board_color_t;

typedef struct {
    bool pressed;
    uint16_t presses;
    uint32_t held_ms;
} board_button_value_t;

typedef struct {
    board_state_t state;
    board_pattern_t pattern;
    board_color_t color;
    uint8_t flashes;
} board_led_value_t;

typedef struct {
    board_command_kind_t kind;
    board_color_t color;
    uint8_t count;
} board_command_t;
