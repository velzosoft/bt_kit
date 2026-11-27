#include "lab_database.h"

#include <stdbool.h>
#include <string.h>

#include "esp_log.h"
#include "host/ble_att.h"
#include "host/ble_gatt.h"
#include "host/ble_hs.h"
#include "nimble/nimble_npl.h"
#include "nimble/nimble_port.h"

#include "lab_profile.h"

#define CHANGE_DELAY_MS 200

static const char *TAG = "lab_database";

static const char extra_value[] = "extra";
static const ble_uuid128_t extra_service_uuid =
    LAB_UUID_INIT(LAB_EXTRA_SERVICE_ID);

static bool wanted;
static bool served;
static struct ble_npl_callout change_timer;

static int extra_access(uint16_t conn_handle, uint16_t attr_handle,
                        struct ble_gatt_access_ctxt *ctxt, void *arg)
{
    if (ctxt->op != BLE_GATT_ACCESS_OP_READ_CHR) {
        return BLE_ATT_ERR_UNLIKELY;
    }
    return os_mbuf_append(ctxt->om, extra_value, strlen(extra_value)) == 0
               ? 0
               : BLE_ATT_ERR_INSUFFICIENT_RES;
}

static const struct ble_gatt_svc_def extra_services[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &extra_service_uuid.u,
        .characteristics =
            (struct ble_gatt_chr_def[]){
                {
                    .uuid = LAB_UUID_DECLARE(LAB_EXTRA_CHARACTERISTIC_ID),
                    .access_cb = extra_access,
                    .flags = BLE_GATT_CHR_F_READ,
                },
                {0},
            },
    },
    {0},
};

static void apply_change(struct ble_npl_event *event)
{
    if (wanted == served) {
        return;
    }
    int rc = wanted ? ble_gatts_add_dynamic_svcs(extra_services)
                    : ble_gatts_delete_svc(&extra_service_uuid.u);
    if (rc != 0) {
        ESP_LOGE(TAG, "%s the extra service failed; rc=%d",
                 wanted ? "adding" : "removing", rc);
        wanted = served;
        return;
    }
    served = wanted;
    ESP_LOGI(TAG, "extra service %s", served ? "added" : "removed");
}

void lab_database_init(void)
{
    ble_npl_callout_init(&change_timer, nimble_port_get_dflt_eventq(),
                         apply_change, NULL);
}

int lab_database_command(const uint8_t *data, uint16_t length)
{
    if (length != 1) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }
    if (data[0] > 1) {
        return BLE_ATT_ERR_VALUE_NOT_ALLOWED;
    }
    if (data[0] != wanted) {
        wanted = data[0];
        ble_npl_callout_reset(&change_timer,
                              ble_npl_time_ms_to_ticks32(CHANGE_DELAY_MS));
    }
    return 0;
}

int lab_database_append_state(struct os_mbuf *om)
{
    uint8_t state = wanted;
    return os_mbuf_append(om, &state, sizeof state) == 0
               ? 0
               : BLE_ATT_ERR_INSUFFICIENT_RES;
}
