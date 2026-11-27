#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "host/ble_hs.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "nvs_flash.h"
#include "services/gap/ble_svc_gap.h"

#include "board_button.h"
#include "board_gatt.h"
#include "board_led.h"
#include "board_led_driver.h"
#include "board_profile.h"

#define QUEUE_LENGTH 32
#define BOARD_TASK_STACK 4096
#define BOARD_TASK_PRIORITY 5
#define RENDER_PERIOD_US 20000
#define LINK_LOST_FLASHES 2
#define ADVERTISING_INTERVAL_MIN BLE_GAP_ADV_ITVL_MS(20)
#define ADVERTISING_INTERVAL_MAX BLE_GAP_ADV_ITVL_MS(30)
#define CONNECTION_INTERVAL_MIN BLE_GAP_CONN_ITVL_MS(15)
#define CONNECTION_INTERVAL_MAX BLE_GAP_CONN_ITVL_MS(30)
#define SUPERVISION_TIMEOUT BLE_GAP_SUPERVISION_TIMEOUT_MS(4000)
#define NAME_LENGTH (sizeof BOARD_NAME_PREFIX + 4)
#define STATIC_RANDOM_BITS 0xc0
#define DISTINCT_ADDRESS_BIT 0x20

static const char *TAG = "board";

static const char *const state_names[BOARD_STATES] = {
    [BOARD_STATE_STARTING] = "starting",
    [BOARD_STATE_WAITING] = "waiting",
    [BOARD_STATE_CONNECTED] = "connected",
    [BOARD_STATE_READY] = "ready",
    [BOARD_STATE_ERROR] = "error",
};

static const board_color_t link_lost_color = {0xff, 0x00, 0x00};
static const ble_uuid128_t board_service = BOARD_UUID_INIT(BOARD_SERVICE_ID);

typedef enum {
    EVENT_ADVERTISING,
    EVENT_HOST_RESET,
    EVENT_CONNECTED,
    EVENT_DISCONNECTED,
    EVENT_SUBSCRIPTION,
    EVENT_BUTTON,
    EVENT_COMMAND,
    EVENT_TICK,
} event_kind_t;

typedef struct {
    event_kind_t kind;
    int64_t at_us;
    union {
        uint16_t conn_handle;
        struct {
            uint16_t attr_handle;
            bool notify;
        } subscription;
        bool pressed;
        board_command_t command;
    };
} board_event_t;

void ble_store_config_init(void);

static QueueHandle_t events;
static uint8_t own_address_type;
static char name[NAME_LENGTH];
static bool linked;

static struct {
    uint16_t conn_handle;
    uint16_t presses;
    int64_t pressed_at_us;
} board = {.conn_handle = BLE_HS_CONN_HANDLE_NONE};

static bool post(board_event_t event)
{
    if (event.at_us == 0) {
        event.at_us = esp_timer_get_time();
    }
    if (xQueueSend(events, &event, 0) == pdTRUE) {
        return true;
    }
    if (event.kind != EVENT_TICK) {
        ESP_LOGW(TAG, "event queue full; event %d dropped", event.kind);
    }
    return false;
}

static void post_button(bool pressed, int64_t at_us)
{
    post((board_event_t){
        .kind = EVENT_BUTTON,
        .at_us = at_us,
        .pressed = pressed,
    });
}

static bool post_command(const board_command_t *command)
{
    return post((board_event_t){.kind = EVENT_COMMAND, .command = *command});
}

static void post_tick(void *arg)
{
    post((board_event_t){.kind = EVENT_TICK});
}

static void set_state(board_state_t state)
{
    board_state_t old = board_led_state();
    if (old == state) {
        return;
    }
    ESP_LOGI(TAG, "state %s -> %s", state_names[old], state_names[state]);
    board_led_set_state(state);
}

static void on_connected(uint16_t conn_handle)
{
    board.conn_handle = conn_handle;
    board_gatt_connected(conn_handle);
    set_state(BOARD_STATE_CONNECTED);
}

static void on_disconnected(int64_t now_us)
{
    bool was_linked = board.conn_handle != BLE_HS_CONN_HANDLE_NONE;
    board.conn_handle = BLE_HS_CONN_HANDLE_NONE;
    board_gatt_disconnected();
    if (was_linked) {
        board_led_flash(link_lost_color, LINK_LOST_FLASHES, now_us);
        set_state(BOARD_STATE_WAITING);
    }
}

static void on_host_reset(void)
{
    board.conn_handle = BLE_HS_CONN_HANDLE_NONE;
    board_gatt_disconnected();
    set_state(BOARD_STATE_ERROR);
}

static void on_subscription(uint16_t attr_handle, bool notify)
{
    board_gatt_subscription(attr_handle, notify);
    if (attr_handle == board_gatt_button_handle() &&
        board.conn_handle != BLE_HS_CONN_HANDLE_NONE) {
        set_state(notify ? BOARD_STATE_READY : BOARD_STATE_CONNECTED);
    }
}

static void on_button(bool pressed, int64_t at_us, int64_t now_us)
{
    board_button_value_t value = {.pressed = pressed};
    if (pressed) {
        board.presses++;
        board.pressed_at_us = at_us;
        ESP_LOGI(TAG, "press %u", board.presses);
    } else {
        value.held_ms = (uint32_t)((at_us - board.pressed_at_us) / 1000);
        ESP_LOGI(TAG, "release %u after %lu ms", board.presses,
                 (unsigned long)value.held_ms);
    }
    value.presses = board.presses;
    board_gatt_publish_button(&value, board.pressed_at_us);
    board_led_hold(pressed, now_us);
}

static void on_command(const board_command_t *command, int64_t now_us)
{
    if (command->kind == BOARD_COMMAND_STOP) {
        ESP_LOGI(TAG, "command: stop flashing");
        board_led_stop_flashing();
        return;
    }
    ESP_LOGI(TAG, "command: flash %02x%02x%02x, count %u",
             command->color.red, command->color.green, command->color.blue,
             command->count);
    board_led_flash(command->color, command->count, now_us);
}

static void handle(const board_event_t *event, int64_t now_us)
{
    switch (event->kind) {
    case EVENT_ADVERTISING:
        set_state(BOARD_STATE_WAITING);
        break;
    case EVENT_HOST_RESET:
        on_host_reset();
        break;
    case EVENT_CONNECTED:
        on_connected(event->conn_handle);
        break;
    case EVENT_DISCONNECTED:
        on_disconnected(now_us);
        break;
    case EVENT_SUBSCRIPTION:
        on_subscription(event->subscription.attr_handle,
                        event->subscription.notify);
        break;
    case EVENT_BUTTON:
        on_button(event->pressed, event->at_us, now_us);
        break;
    case EVENT_COMMAND:
        on_command(&event->command, now_us);
        break;
    case EVENT_TICK:
        break;
    }
}

static void board_task(void *param)
{
    board_led_value_t value;
    board_led_refresh(esp_timer_get_time(), &value);
    board_gatt_publish_led(&value);
    board_event_t event;
    for (;;) {
        if (xQueueReceive(events, &event, portMAX_DELAY) != pdTRUE) {
            continue;
        }
        int64_t now_us = esp_timer_get_time();
        handle(&event, now_us);
        if (board_led_refresh(now_us, &value)) {
            board_gatt_publish_led(&value);
        }
        board_led_render(now_us);
    }
}

static void log_parameters(uint16_t conn_handle)
{
    struct ble_gap_conn_desc desc;
    if (ble_gap_conn_find(conn_handle, &desc) != 0) {
        return;
    }
    ESP_LOGI(TAG, "connection interval %u.%02u ms, latency %u, timeout %u ms",
             desc.conn_itvl * 125 / 100, desc.conn_itvl * 125 % 100,
             desc.conn_latency, desc.supervision_timeout * 10);
}

static void request_parameters(uint16_t conn_handle)
{
    struct ble_gap_upd_params params = {
        .itvl_min = CONNECTION_INTERVAL_MIN,
        .itvl_max = CONNECTION_INTERVAL_MAX,
        .latency = 0,
        .supervision_timeout = SUPERVISION_TIMEOUT,
    };
    int rc = ble_gap_update_params(conn_handle, &params);
    if (rc != 0) {
        ESP_LOGW(TAG, "connection parameter request failed; rc=%d", rc);
    }
}

static int on_gap_event(struct ble_gap_event *event, void *arg);

static void advertise(void)
{
    if (linked || ble_gap_adv_active()) {
        return;
    }
    struct ble_gap_adv_params params = {
        .conn_mode = BLE_GAP_CONN_MODE_UND,
        .disc_mode = BLE_GAP_DISC_MODE_GEN,
        .itvl_min = ADVERTISING_INTERVAL_MIN,
        .itvl_max = ADVERTISING_INTERVAL_MAX,
    };
    int rc = ble_gap_adv_start(own_address_type, NULL, BLE_HS_FOREVER, &params,
                               on_gap_event, NULL);
    if (rc != 0) {
        ESP_LOGE(TAG, "advertising failed to start; rc=%d", rc);
        return;
    }
    post((board_event_t){.kind = EVENT_ADVERTISING});
}

static int on_gap_event(struct ble_gap_event *event, void *arg)
{
    switch (event->type) {
    case BLE_GAP_EVENT_CONNECT:
        if (event->connect.status != 0) {
            ESP_LOGW(TAG, "connection failed; status=%d",
                     event->connect.status);
            advertise();
            return 0;
        }
        linked = true;
        ESP_LOGI(TAG, "connection %d opened", event->connect.conn_handle);
        log_parameters(event->connect.conn_handle);
        request_parameters(event->connect.conn_handle);
        post((board_event_t){
            .kind = EVENT_CONNECTED,
            .conn_handle = event->connect.conn_handle,
        });
        return 0;
    case BLE_GAP_EVENT_DISCONNECT:
        linked = false;
        ESP_LOGI(TAG, "connection %d closed; reason=0x%x",
                 event->disconnect.conn.conn_handle, event->disconnect.reason);
        post((board_event_t){.kind = EVENT_DISCONNECTED});
        advertise();
        return 0;
    case BLE_GAP_EVENT_ADV_COMPLETE:
        advertise();
        return 0;
    case BLE_GAP_EVENT_CONN_UPDATE:
        if (event->conn_update.status == 0) {
            log_parameters(event->conn_update.conn_handle);
        } else {
            ESP_LOGW(TAG, "connection parameter update failed; status=%d",
                     event->conn_update.status);
        }
        return 0;
    case BLE_GAP_EVENT_SUBSCRIBE:
        if (event->subscribe.reason != BLE_GAP_SUBSCRIBE_REASON_TERM) {
            post((board_event_t){
                .kind = EVENT_SUBSCRIPTION,
                .subscription = {event->subscribe.attr_handle,
                                 event->subscribe.cur_notify},
            });
        }
        return 0;
    case BLE_GAP_EVENT_ENC_CHANGE:
        if (event->enc_change.status != 0) {
            ESP_LOGW(TAG, "connection %d encryption failed; status=0x%x",
                     event->enc_change.conn_handle, event->enc_change.status);
        }
        return 0;
    case BLE_GAP_EVENT_MTU:
        ESP_LOGI(TAG, "connection %d MTU %d", event->mtu.conn_handle,
                 event->mtu.value);
        return 0;
    default:
        return 0;
    }
}

static int configure_advertising(void)
{
    struct ble_hs_adv_fields advertisement = {
        .flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP,
        .uuids128 = &board_service,
        .num_uuids128 = 1,
        .uuids128_is_complete = 1,
    };
    int rc = ble_gap_adv_set_fields(&advertisement);
    if (rc != 0) {
        return rc;
    }
    struct ble_hs_adv_fields scan_response = {
        .name = (const uint8_t *)name,
        .name_len = strlen(name),
        .name_is_complete = 1,
    };
    return ble_gap_adv_rsp_set_fields(&scan_response);
}

static void log_address(const char *label, const uint8_t address[6])
{
    ESP_LOGI(TAG, "%s %02x:%02x:%02x:%02x:%02x:%02x", label, address[5],
             address[4], address[3], address[2], address[1], address[0]);
}

static void use_board_address(void)
{
    uint8_t address[6];
    int rc = ble_hs_id_copy_addr(BLE_ADDR_PUBLIC, address, NULL);
    assert(rc == 0);
    log_address("chip address", address);
    uint8_t top = address[5] | STATIC_RANDOM_BITS;
    address[5] = top == address[5] ? top ^ DISTINCT_ADDRESS_BIT : top;
    rc = ble_hs_id_set_rnd(address);
    assert(rc == 0);
    own_address_type = BLE_OWN_ADDR_RANDOM;
    snprintf(name, sizeof name, BOARD_NAME_PREFIX "%02X%02X", address[1],
             address[0]);
    log_address(name, address);
}

static void on_sync(void)
{
    use_board_address();
    int rc = ble_svc_gap_device_name_set(name);
    assert(rc == 0);
    rc = configure_advertising();
    assert(rc == 0);
    advertise();
}

static void on_reset(int reason)
{
    ESP_LOGW(TAG, "host reset; reason=%d", reason);
    linked = false;
    post((board_event_t){.kind = EVENT_HOST_RESET});
}

static void configure_security(void)
{
    ble_hs_cfg.sm_io_cap = BLE_SM_IO_CAP_NO_IO;
    ble_hs_cfg.sm_bonding = 0;
    ble_hs_cfg.sm_mitm = 0;
    ble_hs_cfg.sm_sc = 1;
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

static void start_render_tick(void)
{
    const esp_timer_create_args_t args = {
        .callback = post_tick,
        .name = "board_render",
    };
    esp_timer_handle_t timer;
    ESP_ERROR_CHECK(esp_timer_create(&args, &timer));
    ESP_ERROR_CHECK(esp_timer_start_periodic(timer, RENDER_PERIOD_US));
}

void app_main(void)
{
    init_nvs();
    events = xQueueCreate(QUEUE_LENGTH, sizeof(board_event_t));
    assert(events != NULL);
    ESP_ERROR_CHECK(board_led_driver_init());
    board_led_kind_t kind = board_led_driver_kind();
    int64_t now_us = esp_timer_get_time();
    board_led_init(kind, now_us);
    board_led_render(now_us);
    ESP_ERROR_CHECK(nimble_port_init());
    ble_hs_cfg.sync_cb = on_sync;
    ble_hs_cfg.reset_cb = on_reset;
    configure_security();
    ESP_ERROR_CHECK(board_gatt_init(kind, post_command));
    ble_store_config_init();
    xTaskCreate(board_task, "board", BOARD_TASK_STACK, NULL,
                BOARD_TASK_PRIORITY, NULL);
    ESP_ERROR_CHECK(board_button_init(post_button));
    start_render_tick();
    nimble_port_freertos_init(host_task);
}
