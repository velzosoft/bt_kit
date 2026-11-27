#include "lab_gatt.h"

#include <stdio.h>
#include <string.h>

#include "esp_app_desc.h"
#include "esp_chip_info.h"
#include "esp_idf_version.h"
#include "host/ble_att.h"
#include "host/ble_gatt.h"
#include "host/ble_hs.h"
#include "sdkconfig.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

#include "lab_database.h"
#include "lab_stream.h"

#define LONG_VALUE_PERIOD 251
#define MAX_COMMAND_LENGTH 4

typedef enum {
    LAB_FIXED_VALUE = 0x101,
    LAB_ECHO = 0x102,
    LAB_NOTIFY_STREAM = 0x103,
    LAB_INDICATE_STREAM = 0x104,
    LAB_LONG_VALUE = 0x105,
    LAB_ENCRYPTED_VALUE = 0x106,
    LAB_FAULT_CONTROL = 0x107,
    LAB_FAULT_TARGET = 0x108,
    LAB_STREAM_CONTROL = 0x109,
    LAB_INFO = 0x10a,
    LAB_DATABASE_CONTROL = 0x10b,
    LAB_INCLUDED_VALUE = LAB_INCLUDED_CHARACTERISTIC_ID,
} lab_attribute_t;

static const char fixed_value[] = "bt_kit lab v1";
static const char encrypted_value[] = "encrypted ok";
static const char fault_target_value[] = "no fault";
static const char included_value[] = "included";

static uint8_t long_value[LAB_MAX_VALUE_LENGTH];
static uint8_t echo[LAB_MAX_VALUE_LENGTH];
static uint16_t echo_length;
static uint8_t fault;
static char info[LAB_MAX_INFO_LENGTH + 1];
static uint16_t stream_handles[LAB_STREAM_KINDS];

static int lab_access(uint16_t conn_handle, uint16_t attr_handle,
                      struct ble_gatt_access_ctxt *ctxt, void *arg);

#define LAB_CHARACTERISTIC(id, chr_flags, ...)                                 \
    {                                                                          \
        .uuid = LAB_UUID_DECLARE(id),                                          \
        .access_cb = lab_access,                                               \
        .arg = (void *)(uintptr_t)(id),                                        \
        .flags = (chr_flags),                                                  \
        __VA_ARGS__                                                            \
    }

static const struct ble_gatt_svc_def services[3];

static const struct ble_gatt_svc_def *lab_includes[] = {&services[0], NULL};

static const struct ble_gatt_svc_def services[3] = {
    {
        .type = BLE_GATT_SVC_TYPE_SECONDARY,
        .uuid = LAB_UUID_DECLARE(LAB_INCLUDED_SERVICE_ID),
        .characteristics =
            (struct ble_gatt_chr_def[]){
                LAB_CHARACTERISTIC(LAB_INCLUDED_VALUE, BLE_GATT_CHR_F_READ),
                {0},
            },
    },
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = LAB_UUID_DECLARE(LAB_SERVICE_ID),
        .includes = lab_includes,
        .characteristics =
            (struct ble_gatt_chr_def[]){
                LAB_CHARACTERISTIC(LAB_FIXED_VALUE, BLE_GATT_CHR_F_READ),
                LAB_CHARACTERISTIC(LAB_ECHO, BLE_GATT_CHR_F_READ |
                                                 BLE_GATT_CHR_F_WRITE |
                                                 BLE_GATT_CHR_F_WRITE_NO_RSP),
                LAB_CHARACTERISTIC(
                    LAB_NOTIFY_STREAM, BLE_GATT_CHR_F_NOTIFY,
                    .val_handle = &stream_handles[LAB_STREAM_NOTIFY]),
                LAB_CHARACTERISTIC(
                    LAB_INDICATE_STREAM, BLE_GATT_CHR_F_INDICATE,
                    .val_handle = &stream_handles[LAB_STREAM_INDICATE]),
                LAB_CHARACTERISTIC(LAB_LONG_VALUE, BLE_GATT_CHR_F_READ),
                LAB_CHARACTERISTIC(LAB_ENCRYPTED_VALUE,
                                   BLE_GATT_CHR_F_READ |
                                       BLE_GATT_CHR_F_READ_ENC),
                LAB_CHARACTERISTIC(LAB_FAULT_CONTROL,
                                   BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_WRITE),
                LAB_CHARACTERISTIC(LAB_FAULT_TARGET, BLE_GATT_CHR_F_READ),
                LAB_CHARACTERISTIC(LAB_STREAM_CONTROL,
                                   BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_WRITE),
                LAB_CHARACTERISTIC(LAB_INFO, BLE_GATT_CHR_F_READ),
                LAB_CHARACTERISTIC(LAB_DATABASE_CONTROL,
                                   BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_WRITE),
                {0},
            },
    },
    {0},
};

static int append(struct os_mbuf *om, const void *data, uint16_t length)
{
    return os_mbuf_append(om, data, length) == 0
               ? 0
               : BLE_ATT_ERR_INSUFFICIENT_RES;
}

static int append_text(struct os_mbuf *om, const char *text)
{
    return append(om, text, strlen(text));
}

static int read_value(lab_attribute_t attribute, struct os_mbuf *om)
{
    switch (attribute) {
    case LAB_FIXED_VALUE:
        return append_text(om, fixed_value);
    case LAB_ECHO:
        return append(om, echo, echo_length);
    case LAB_LONG_VALUE:
        return append(om, long_value, sizeof long_value);
    case LAB_ENCRYPTED_VALUE:
        return append_text(om, encrypted_value);
    case LAB_FAULT_CONTROL:
        return append(om, &fault, sizeof fault);
    case LAB_FAULT_TARGET:
        return fault != 0 ? fault : append_text(om, fault_target_value);
    case LAB_STREAM_CONTROL:
        return lab_stream_append_command(om);
    case LAB_INFO:
        return append_text(om, info);
    case LAB_DATABASE_CONTROL:
        return lab_database_append_state(om);
    case LAB_INCLUDED_VALUE:
        return append_text(om, included_value);
    default:
        return BLE_ATT_ERR_READ_NOT_PERMITTED;
    }
}

static int write_echo(const struct os_mbuf *om)
{
    uint16_t length = OS_MBUF_PKTLEN(om);
    if (length > sizeof echo) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }
    if (os_mbuf_copydata(om, 0, length, echo) != 0) {
        return BLE_ATT_ERR_UNLIKELY;
    }
    echo_length = length;
    return 0;
}

static int write_fault(const uint8_t *data, uint16_t length)
{
    if (length != 1) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }
    if (data[0] > BLE_ATT_ERR_VALUE_NOT_ALLOWED) {
        return BLE_ATT_ERR_VALUE_NOT_ALLOWED;
    }
    fault = data[0];
    return 0;
}

static int write_value(lab_attribute_t attribute, const struct os_mbuf *om)
{
    if (attribute == LAB_ECHO) {
        return write_echo(om);
    }
    uint8_t command[MAX_COMMAND_LENGTH];
    uint16_t length = OS_MBUF_PKTLEN(om);
    uint16_t copied = length < sizeof command ? length : sizeof command;
    if (os_mbuf_copydata(om, 0, copied, command) != 0) {
        return BLE_ATT_ERR_UNLIKELY;
    }
    switch (attribute) {
    case LAB_FAULT_CONTROL:
        return write_fault(command, length);
    case LAB_STREAM_CONTROL:
        return lab_stream_command(command, length);
    case LAB_DATABASE_CONTROL:
        return lab_database_command(command, length);
    default:
        return BLE_ATT_ERR_WRITE_NOT_PERMITTED;
    }
}

static int lab_access(uint16_t conn_handle, uint16_t attr_handle,
                      struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    lab_attribute_t attribute = (lab_attribute_t)(uintptr_t)arg;
    switch (ctxt->op) {
    case BLE_GATT_ACCESS_OP_READ_CHR:
        return read_value(attribute, ctxt->om);
    case BLE_GATT_ACCESS_OP_WRITE_CHR:
        return write_value(attribute, ctxt->om);
    default:
        return BLE_ATT_ERR_UNLIKELY;
    }
}

static void describe_device(void)
{
    esp_chip_info_t chip;
    esp_chip_info(&chip);
    snprintf(info, sizeof info, "%s rev%d.%d esp-idf %.12s nimble fw %.12s",
             CONFIG_IDF_TARGET, chip.revision / 100, chip.revision % 100,
             esp_get_idf_version(), esp_app_get_description()->version);
}

int lab_gatt_init(void)
{
    for (size_t i = 0; i < sizeof long_value; i++) {
        long_value[i] = i % LONG_VALUE_PERIOD;
    }
    describe_device();
    ble_svc_gap_init();
    ble_svc_gatt_init();
    int rc = ble_gatts_count_cfg(services);
    if (rc != 0) {
        return rc;
    }
    return ble_gatts_add_svcs(services);
}

uint16_t lab_gatt_stream_handle(lab_stream_kind_t kind)
{
    return stream_handles[kind];
}
