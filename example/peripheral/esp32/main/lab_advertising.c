#include "lab_advertising.h"

#include <string.h>

#include "esp_log.h"
#include "host/ble_hs.h"
#include "host/ble_hs_adv.h"

#include "lab_profile.h"

#define INTERVAL_MIN_UNITS 32
#define INTERVAL_MAX_UNITS 48

static const char *TAG = "lab_advertising";

static const ble_uuid128_t lab_service = LAB_UUID_INIT(LAB_SERVICE_ID);

static const uint8_t manufacturer_data[] = {
    LAB_MANUFACTURER_ID & 0xff,
    LAB_MANUFACTURER_ID >> 8,
    LAB_MARKER_BYTE,
};

static const uint8_t service_data[] = {
    LAB_UUID_BYTES(LAB_SERVICE_ID),
    LAB_MARKER_BYTE,
};

static uint8_t address_type;
static ble_gap_event_fn *event_handler;

static int set_advertisement(void)
{
    struct ble_hs_adv_fields fields = {
        .flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP,
        .uuids128 = &lab_service,
        .num_uuids128 = 1,
        .uuids128_is_complete = 1,
        .mfg_data = manufacturer_data,
        .mfg_data_len = sizeof manufacturer_data,
    };
    return ble_gap_adv_set_fields(&fields);
}

static int set_scan_response(void)
{
    struct ble_hs_adv_fields fields = {
        .name = (const uint8_t *)LAB_LOCAL_NAME,
        .name_len = strlen(LAB_LOCAL_NAME),
        .name_is_complete = 1,
        .svc_data_uuid128 = service_data,
        .svc_data_uuid128_len = sizeof service_data,
    };
    return ble_gap_adv_rsp_set_fields(&fields);
}

int lab_advertising_configure(uint8_t own_addr_type, ble_gap_event_fn *on_event)
{
    address_type = own_addr_type;
    event_handler = on_event;
    int rc = set_advertisement();
    if (rc != 0) {
        return rc;
    }
    return set_scan_response();
}

void lab_advertising_start(void)
{
    if (ble_gap_adv_active()) {
        return;
    }
    struct ble_gap_adv_params params = {
        .conn_mode = BLE_GAP_CONN_MODE_UND,
        .disc_mode = BLE_GAP_DISC_MODE_GEN,
        .itvl_min = INTERVAL_MIN_UNITS,
        .itvl_max = INTERVAL_MAX_UNITS,
    };
    int rc = ble_gap_adv_start(address_type, NULL, BLE_HS_FOREVER, &params,
                               event_handler, NULL);
    if (rc != 0) {
        ESP_LOGE(TAG, "advertising failed to start; rc=%d", rc);
    }
}
