#include "board_gatt.h"

#include <stdio.h>
#include <string.h>

#include "esp_app_desc.h"
#include "esp_chip_info.h"
#include "esp_idf_version.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "host/ble_att.h"
#include "host/ble_gatt.h"
#include "host/ble_hs.h"
#include "host/ble_hs_mbuf.h"
#include "sdkconfig.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

#define FLASH_COMMAND_LENGTH 5

static const char *TAG = "board_gatt";

static board_command_handler_t *command_handler;
static portMUX_TYPE lock = portMUX_INITIALIZER_UNLOCKED;
static uint16_t button_handle;
static uint16_t led_handle;
static uint8_t info[1 + BOARD_MAX_INFO_TEXT_LENGTH + 1];
static uint16_t info_length;

static struct {
    board_button_value_t value;
    int64_t pressed_at_us;
} button;

static board_led_value_t led;

static struct {
    uint16_t conn_handle;
    bool button;
    bool led;
} link = {.conn_handle = BLE_HS_CONN_HANDLE_NONE};

static int board_access(uint16_t conn_handle, uint16_t attr_handle,
                        struct ble_gatt_access_ctxt *ctxt, void *arg);

#define BOARD_CHARACTERISTIC(id, chr_flags, ...)                               \
    {                                                                          \
        .uuid = BOARD_UUID_DECLARE(id),                                        \
        .access_cb = board_access,                                             \
        .arg = (void *)(uintptr_t)(id),                                        \
        .flags = (chr_flags),                                                  \
        __VA_ARGS__                                                            \
    }

static const struct ble_gatt_svc_def services[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = BOARD_UUID_DECLARE(BOARD_SERVICE_ID),
        .characteristics =
            (struct ble_gatt_chr_def[]){
                BOARD_CHARACTERISTIC(BOARD_BUTTON_ID,
                                     BLE_GATT_CHR_F_READ |
                                         BLE_GATT_CHR_F_NOTIFY,
                                     .val_handle = &button_handle),
                BOARD_CHARACTERISTIC(BOARD_LED_COMMAND_ID,
                                     BLE_GATT_CHR_F_WRITE |
                                         BLE_GATT_CHR_F_WRITE_NO_RSP),
                BOARD_CHARACTERISTIC(BOARD_LED_ID,
                                     BLE_GATT_CHR_F_READ |
                                         BLE_GATT_CHR_F_NOTIFY,
                                     .val_handle = &led_handle),
                BOARD_CHARACTERISTIC(BOARD_INFO_ID, BLE_GATT_CHR_F_READ),
                {0},
            },
    },
    {0},
};

static void put_le(uint8_t *out, uint32_t value, int length)
{
    for (int i = 0; i < length; i++) {
        out[i] = (uint8_t)(value >> (8 * i));
    }
}

static void encode_button(const board_button_value_t *value,
                          uint8_t out[BOARD_BUTTON_VALUE_LENGTH])
{
    out[0] = value->pressed ? 0x01 : 0x00;
    put_le(out + 1, value->presses, 2);
    put_le(out + 3, value->held_ms, 4);
}

static void encode_led(const board_led_value_t *value,
                       uint8_t out[BOARD_LED_VALUE_LENGTH])
{
    out[0] = value->state;
    out[1] = value->pattern;
    out[2] = value->color.red;
    out[3] = value->color.green;
    out[4] = value->color.blue;
    out[5] = value->flashes;
}

static board_button_value_t button_now(void)
{
    taskENTER_CRITICAL(&lock);
    board_button_value_t value = button.value;
    int64_t pressed_at_us = button.pressed_at_us;
    taskEXIT_CRITICAL(&lock);
    if (value.pressed) {
        int64_t held_us = esp_timer_get_time() - pressed_at_us;
        value.held_ms = (uint32_t)(held_us / 1000);
    }
    return value;
}

static board_led_value_t led_now(void)
{
    taskENTER_CRITICAL(&lock);
    board_led_value_t value = led;
    taskEXIT_CRITICAL(&lock);
    return value;
}

static int append(struct os_mbuf *om, const void *data, uint16_t length)
{
    return os_mbuf_append(om, data, length) == 0
               ? 0
               : BLE_ATT_ERR_INSUFFICIENT_RES;
}

static int read_value(uint16_t id, struct os_mbuf *om)
{
    switch (id) {
    case BOARD_BUTTON_ID: {
        uint8_t value[BOARD_BUTTON_VALUE_LENGTH];
        board_button_value_t now = button_now();
        encode_button(&now, value);
        return append(om, value, sizeof value);
    }
    case BOARD_LED_ID: {
        uint8_t value[BOARD_LED_VALUE_LENGTH];
        board_led_value_t now = led_now();
        encode_led(&now, value);
        return append(om, value, sizeof value);
    }
    case BOARD_INFO_ID:
        return append(om, info, info_length);
    default:
        return BLE_ATT_ERR_READ_NOT_PERMITTED;
    }
}

static int parse_command(const uint8_t *bytes, uint16_t length,
                         board_command_t *command)
{
    if (length == 0) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }
    switch (bytes[0]) {
    case BOARD_COMMAND_STOP:
        if (length != 1) {
            return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
        }
        *command = (board_command_t){.kind = BOARD_COMMAND_STOP};
        return 0;
    case BOARD_COMMAND_FLASH:
        if (length != FLASH_COMMAND_LENGTH) {
            return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
        }
        if (bytes[4] == 0 || bytes[4] > BOARD_MAX_FLASHES) {
            return BLE_ATT_ERR_VALUE_NOT_ALLOWED;
        }
        *command = (board_command_t){
            .kind = BOARD_COMMAND_FLASH,
            .color = {bytes[1], bytes[2], bytes[3]},
            .count = bytes[4],
        };
        return 0;
    default:
        return BLE_ATT_ERR_VALUE_NOT_ALLOWED;
    }
}

static int write_command(const struct os_mbuf *om)
{
    uint8_t bytes[FLASH_COMMAND_LENGTH];
    uint16_t length = OS_MBUF_PKTLEN(om);
    uint16_t copied = length < sizeof bytes ? length : sizeof bytes;
    if (os_mbuf_copydata(om, 0, copied, bytes) != 0) {
        return BLE_ATT_ERR_UNLIKELY;
    }
    board_command_t command;
    int rc = parse_command(bytes, length, &command);
    if (rc != 0) {
        ESP_LOGW(TAG, "LED command of %u bytes refused with ATT error 0x%02x",
                 length, rc);
        return rc;
    }
    return command_handler(&command) ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
}

static int board_access(uint16_t conn_handle, uint16_t attr_handle,
                        struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    uint16_t id = (uint16_t)(uintptr_t)arg;
    switch (ctxt->op) {
    case BLE_GATT_ACCESS_OP_READ_CHR:
        return read_value(id, ctxt->om);
    case BLE_GATT_ACCESS_OP_WRITE_CHR:
        return id == BOARD_LED_COMMAND_ID ? write_command(ctxt->om)
                                          : BLE_ATT_ERR_WRITE_NOT_PERMITTED;
    default:
        return BLE_ATT_ERR_UNLIKELY;
    }
}

static void describe_device(board_led_kind_t kind)
{
    esp_chip_info_t chip;
    esp_chip_info(&chip);
    info[0] = kind;
    snprintf((char *)info + 1, sizeof info - 1,
             "%s rev%d.%d esp-idf %.12s fw %.12s", CONFIG_IDF_TARGET,
             chip.revision / 100, chip.revision % 100, esp_get_idf_version(),
             esp_app_get_description()->version);
    info_length = 1 + strlen((char *)info + 1);
}

static void notify(uint16_t handle, const uint8_t *data, uint16_t length)
{
    struct os_mbuf *om = ble_hs_mbuf_from_flat(data, length);
    if (om == NULL) {
        ESP_LOGW(TAG, "no memory for a notification");
        return;
    }
    int rc = ble_gatts_notify_custom(link.conn_handle, handle, om);
    if (rc != 0) {
        ESP_LOGW(TAG, "notification failed; rc=%d", rc);
    }
}

int board_gatt_init(board_led_kind_t kind, board_command_handler_t *on_command)
{
    command_handler = on_command;
    describe_device(kind);
    ble_svc_gap_init();
    ble_svc_gatt_init();
    int rc = ble_gatts_count_cfg(services);
    if (rc != 0) {
        return rc;
    }
    return ble_gatts_add_svcs(services);
}

uint16_t board_gatt_button_handle(void)
{
    return button_handle;
}

void board_gatt_connected(uint16_t conn_handle)
{
    link.conn_handle = conn_handle;
    link.button = false;
    link.led = false;
}

void board_gatt_disconnected(void)
{
    board_gatt_connected(BLE_HS_CONN_HANDLE_NONE);
}

void board_gatt_subscription(uint16_t attr_handle, bool notify)
{
    if (attr_handle == button_handle) {
        link.button = notify;
    } else if (attr_handle == led_handle) {
        link.led = notify;
    }
}

void board_gatt_publish_button(const board_button_value_t *value,
                               int64_t pressed_at_us)
{
    taskENTER_CRITICAL(&lock);
    button.value = *value;
    button.pressed_at_us = pressed_at_us;
    taskEXIT_CRITICAL(&lock);
    if (link.conn_handle != BLE_HS_CONN_HANDLE_NONE && link.button) {
        uint8_t bytes[BOARD_BUTTON_VALUE_LENGTH];
        encode_button(value, bytes);
        notify(button_handle, bytes, sizeof bytes);
    }
}

void board_gatt_publish_led(const board_led_value_t *value)
{
    taskENTER_CRITICAL(&lock);
    led = *value;
    taskEXIT_CRITICAL(&lock);
    if (link.conn_handle != BLE_HS_CONN_HANDLE_NONE && link.led) {
        uint8_t bytes[BOARD_LED_VALUE_LENGTH];
        encode_led(value, bytes);
        notify(led_handle, bytes, sizeof bytes);
    }
}
