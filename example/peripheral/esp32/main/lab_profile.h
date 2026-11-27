#pragma once

#include "host/ble_uuid.h"

#define LAB_UUID_BYTES(id)                                                     \
    0x00, 0x1a, 0x0b, 0x8e, 0x2d, 0x7c, 0x54, 0x9a, 0x7a, 0x4e, 0x2c, 0x6b,    \
        ((id) & 0xff), (0xa0 | ((id) >> 8)), 0xb1, 0xf3

#define LAB_UUID_INIT(id) BLE_UUID128_INIT(LAB_UUID_BYTES(id))
#define LAB_UUID_DECLARE(id) BLE_UUID128_DECLARE(LAB_UUID_BYTES(id))

#define LAB_SERVICE_ID 0x100
#define LAB_EXTRA_SERVICE_ID 0x110
#define LAB_EXTRA_CHARACTERISTIC_ID 0x111
#define LAB_INCLUDED_SERVICE_ID 0x120
#define LAB_INCLUDED_CHARACTERISTIC_ID 0x121

#define LAB_LOCAL_NAME "bt_kit Lab"
#define LAB_MANUFACTURER_ID 0xffff
#define LAB_MARKER_BYTE 0x4c
#define LAB_MAX_VALUE_LENGTH 512
#define LAB_MAX_INFO_LENGTH 64

typedef enum {
    LAB_STREAM_NOTIFY,
    LAB_STREAM_INDICATE,
    LAB_STREAM_KINDS,
} lab_stream_kind_t;
