#include <assert.h>

#include "esp_log.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "nvs_flash.h"
#include "sdkconfig.h"
#include "services/gap/ble_svc_gap.h"

#include "lab_advertising.h"
#include "lab_database.h"
#include "lab_gatt.h"
#include "lab_profile.h"
#include "lab_stream.h"

static const char *TAG = "lab";

static int connections;

void ble_store_config_init(void);

static void advertise(void)
{
    if (connections < CONFIG_BT_NIMBLE_MAX_CONNECTIONS) {
        lab_advertising_start();
    }
}

static int forget_old_bond(uint16_t conn_handle)
{
    struct ble_gap_conn_desc desc;
    if (ble_gap_conn_find(conn_handle, &desc) == 0) {
        ble_store_util_delete_peer(&desc.peer_id_addr);
    }
    ESP_LOGI(TAG, "connection %d paired again; old bond removed", conn_handle);
    return BLE_GAP_REPEAT_PAIRING_RETRY;
}

static int on_gap_event(struct ble_gap_event *event, void *arg)
{
    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        if (event->connect.status == 0) {
            connections++;
            lab_stream_on_connect(event->connect.conn_handle);
            ESP_LOGI(TAG, "connection %d opened; %d connected",
                     event->connect.conn_handle, connections);
        }
        advertise();
        return 0;
    case BLE_GAP_EVENT_DISCONNECT:
        connections--;
        lab_stream_on_disconnect(event->disconnect.conn.conn_handle);
        ESP_LOGI(TAG, "connection %d closed; reason=0x%x",
                 event->disconnect.conn.conn_handle, event->disconnect.reason);
        advertise();
        return 0;
    case BLE_GAP_EVENT_ADV_COMPLETE:
        advertise();
        return 0;
    case BLE_GAP_EVENT_SUBSCRIBE:
        lab_stream_on_subscribe(event);
        return 0;
    case BLE_GAP_EVENT_NOTIFY_TX:
        lab_stream_on_notify_tx(event);
        return 0;
    case BLE_GAP_EVENT_MTU:
        ESP_LOGI(TAG, "connection %d MTU %d", event->mtu.conn_handle,
                 event->mtu.value);
        return 0;
    case BLE_GAP_EVENT_ENC_CHANGE:
        ESP_LOGI(TAG, "connection %d encryption status=%d",
                 event->enc_change.conn_handle, event->enc_change.status);
        return 0;
    case BLE_GAP_EVENT_REPEAT_PAIRING:
        return forget_old_bond(event->repeat_pairing.conn_handle);
    default:
        return 0;
    }
}

static void on_sync(void)
{
    int rc = ble_hs_util_ensure_addr(0);
    assert(rc == 0);
    uint8_t own_addr_type;
    rc = ble_hs_id_infer_auto(0, &own_addr_type);
    assert(rc == 0);
    uint8_t address[6];
    ble_hs_id_copy_addr(own_addr_type, address, NULL);
    ESP_LOGI(TAG, "serving the Lab profile as %02x:%02x:%02x:%02x:%02x:%02x",
             address[5], address[4], address[3], address[2], address[1],
             address[0]);
    rc = lab_advertising_configure(own_addr_type, on_gap_event);
    assert(rc == 0);
    advertise();
}

static void on_reset(int reason)
{
    ESP_LOGW(TAG, "host reset; reason=%d", reason);
}

static void host_task(void *param)
{
    nimble_port_run();
    nimble_port_freertos_deinit();
}

static void init_nvs(void)
{
    esp_err_t rc = nvs_flash_init();
    if (rc == ESP_ERR_NVS_NO_FREE_PAGES ||
        rc == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        rc = nvs_flash_init();
    }
    ESP_ERROR_CHECK(rc);
}

static void configure_security(void)
{
    ble_hs_cfg.sm_io_cap = BLE_SM_IO_CAP_NO_IO;
    ble_hs_cfg.sm_bonding = 1;
    ble_hs_cfg.sm_mitm = 0;
    ble_hs_cfg.sm_sc = 1;
    ble_hs_cfg.sm_our_key_dist = BLE_SM_PAIR_KEY_DIST_ENC | BLE_SM_PAIR_KEY_DIST_ID;
    ble_hs_cfg.sm_their_key_dist =
        BLE_SM_PAIR_KEY_DIST_ENC | BLE_SM_PAIR_KEY_DIST_ID;
    ble_hs_cfg.store_status_cb = ble_store_util_status_rr;
}

void app_main(void)
{
    init_nvs();
    ESP_ERROR_CHECK(nimble_port_init());
    ble_hs_cfg.sync_cb = on_sync;
    ble_hs_cfg.reset_cb = on_reset;
    configure_security();
    ESP_ERROR_CHECK(lab_gatt_init());
    ESP_ERROR_CHECK(ble_svc_gap_device_name_set(LAB_LOCAL_NAME));
    ble_store_config_init();
    lab_stream_init();
    lab_database_init();
    nimble_port_freertos_init(host_task);
}
