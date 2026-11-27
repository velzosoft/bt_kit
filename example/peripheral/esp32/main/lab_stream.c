#include "lab_stream.h"

#include <stdbool.h>

#include "esp_log.h"
#include "esp_timer.h"
#include "host/ble_att.h"
#include "host/ble_gatt.h"
#include "host/ble_hs.h"
#include "host/ble_hs_mbuf.h"
#include "nimble/nimble_npl.h"
#include "nimble/nimble_port.h"
#include "sdkconfig.h"

#include "lab_gatt.h"

#define COMMAND_STOP 0x00
#define COMMAND_START_NOTIFY 0x01
#define COMMAND_START_INDICATE 0x02
#define START_COMMAND_LENGTH 3
#define MAX_RATE_HZ 1000
#define PACKET_LENGTH 12
#define SUBSCRIBER_WAIT_US 2000000
#define SUBSCRIBER_POLL_US 20000
#define RETRY_US 1000
#define BURST_LIMIT 16
#define MAX_LINKS CONFIG_BT_NIMBLE_MAX_CONNECTIONS

static const char *TAG = "lab_stream";

typedef enum {
    STREAM_IDLE,
    STREAM_WAITING,
    STREAM_RUNNING,
} stream_state_t;

typedef struct {
    uint16_t conn_handle;
    bool subscribed[LAB_STREAM_KINDS];
    bool awaiting_confirmation;
    bool has_packet;
} link_t;

static link_t links[MAX_LINKS];

static struct {
    stream_state_t state;
    lab_stream_kind_t kind;
    uint16_t rate_hz;
    int64_t origin_us;
    uint32_t sequence;
    uint8_t command[START_COMMAND_LENGTH];
    uint8_t command_length;
    struct ble_npl_callout timer;
} stream = {
    .command = {COMMAND_STOP},
    .command_length = 1,
};

static link_t *find_link(uint16_t conn_handle)
{
    for (int i = 0; i < MAX_LINKS; i++) {
        if (links[i].conn_handle == conn_handle) {
            return &links[i];
        }
    }
    return NULL;
}

static void reset_link(link_t *link, uint16_t conn_handle)
{
    *link = (link_t){.conn_handle = conn_handle};
}

static bool has_subscriber(void)
{
    for (int i = 0; i < MAX_LINKS; i++) {
        if (links[i].conn_handle != BLE_HS_CONN_HANDLE_NONE &&
            links[i].subscribed[stream.kind]) {
            return true;
        }
    }
    return false;
}

static bool awaiting_confirmation(void)
{
    for (int i = 0; i < MAX_LINKS; i++) {
        if (links[i].conn_handle != BLE_HS_CONN_HANDLE_NONE &&
            links[i].awaiting_confirmation) {
            return true;
        }
    }
    return false;
}

static void clear_packets(void)
{
    for (int i = 0; i < MAX_LINKS; i++) {
        links[i].has_packet = false;
    }
}

static void schedule_in(int64_t delay_us)
{
    uint32_t ms = delay_us <= 0 ? 0 : (uint32_t)((delay_us + 999) / 1000);
    ble_npl_callout_reset(&stream.timer, ble_npl_time_ms_to_ticks32(ms));
}

static void stop_stream(void)
{
    if (stream.state == STREAM_RUNNING) {
        ESP_LOGI(TAG, "stream stopped after %lu packets",
                 (unsigned long)stream.sequence);
    }
    stream.state = STREAM_IDLE;
    ble_npl_callout_stop(&stream.timer);
}

static void put_le(uint8_t *out, uint64_t value, int length)
{
    for (int i = 0; i < length; i++) {
        out[i] = (uint8_t)(value >> (8 * i));
    }
}

static int send_packet(link_t *link, const uint8_t *packet)
{
    struct os_mbuf *om = ble_hs_mbuf_from_flat(packet, PACKET_LENGTH);
    if (om == NULL) {
        return BLE_HS_ENOMEM;
    }
    uint16_t handle = lab_gatt_stream_handle(stream.kind);
    if (stream.kind == LAB_STREAM_NOTIFY) {
        return ble_gatts_notify_custom(link->conn_handle, handle, om);
    }
    int rc = ble_gatts_indicate_custom(link->conn_handle, handle, om);
    if (rc == 0) {
        link->awaiting_confirmation = true;
    }
    return rc;
}

static int deliver(int64_t elapsed_us)
{
    uint8_t packet[PACKET_LENGTH];
    put_le(packet, stream.sequence, 4);
    put_le(packet + 4, (uint64_t)elapsed_us, 8);
    for (int i = 0; i < MAX_LINKS; i++) {
        link_t *link = &links[i];
        if (link->conn_handle == BLE_HS_CONN_HANDLE_NONE ||
            !link->subscribed[stream.kind] || link->has_packet) {
            continue;
        }
        int rc = send_packet(link, packet);
        if (rc != 0) {
            return rc;
        }
        link->has_packet = true;
    }
    return 0;
}

static void begin_running(int64_t now_us)
{
    stream.state = STREAM_RUNNING;
    stream.origin_us = now_us;
    stream.sequence = 0;
    clear_packets();
    ESP_LOGI(TAG, "%s stream started at %u Hz",
             stream.kind == LAB_STREAM_NOTIFY ? "notify" : "indicate",
             stream.rate_hz);
}

static void pump(struct ble_npl_event *event)
{
    if (stream.state == STREAM_IDLE) {
        return;
    }
    int64_t now_us = esp_timer_get_time();
    if (!has_subscriber()) {
        if (stream.state == STREAM_WAITING &&
            now_us - stream.origin_us < SUBSCRIBER_WAIT_US) {
            schedule_in(SUBSCRIBER_POLL_US);
        } else {
            stop_stream();
        }
        return;
    }
    if (stream.state == STREAM_WAITING) {
        begin_running(now_us);
    }
    for (int burst = 0; burst < BURST_LIMIT; burst++) {
        if (awaiting_confirmation()) {
            return;
        }
        now_us = esp_timer_get_time();
        int64_t due_us = stream.origin_us +
                         (int64_t)stream.sequence * 1000000 / stream.rate_hz;
        if (now_us < due_us) {
            schedule_in(due_us - now_us);
            return;
        }
        if (deliver(now_us - stream.origin_us) != 0) {
            schedule_in(RETRY_US);
            return;
        }
        stream.sequence++;
        clear_packets();
    }
    schedule_in(0);
}

void lab_stream_init(void)
{
    for (int i = 0; i < MAX_LINKS; i++) {
        reset_link(&links[i], BLE_HS_CONN_HANDLE_NONE);
    }
    ble_npl_callout_init(&stream.timer, nimble_port_get_dflt_eventq(), pump,
                         NULL);
}

static void remember(const uint8_t *data, uint8_t length)
{
    for (uint8_t i = 0; i < length; i++) {
        stream.command[i] = data[i];
    }
    stream.command_length = length;
}

int lab_stream_command(const uint8_t *data, uint16_t length)
{
    if (length == 0) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }
    if (data[0] == COMMAND_STOP) {
        if (length != 1) {
            return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
        }
        remember(data, 1);
        stop_stream();
        return 0;
    }
    if (data[0] != COMMAND_START_NOTIFY && data[0] != COMMAND_START_INDICATE) {
        return BLE_ATT_ERR_VALUE_NOT_ALLOWED;
    }
    if (length != START_COMMAND_LENGTH) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }
    uint16_t rate_hz = data[1] | data[2] << 8;
    if (rate_hz == 0 || rate_hz > MAX_RATE_HZ) {
        return BLE_ATT_ERR_VALUE_NOT_ALLOWED;
    }
    remember(data, START_COMMAND_LENGTH);
    stream.kind = data[0] == COMMAND_START_NOTIFY ? LAB_STREAM_NOTIFY
                                                  : LAB_STREAM_INDICATE;
    stream.rate_hz = rate_hz;
    stream.state = STREAM_WAITING;
    stream.origin_us = esp_timer_get_time();
    schedule_in(0);
    return 0;
}

int lab_stream_append_command(struct os_mbuf *om)
{
    return os_mbuf_append(om, stream.command, stream.command_length) == 0
               ? 0
               : BLE_ATT_ERR_INSUFFICIENT_RES;
}

void lab_stream_on_connect(uint16_t conn_handle)
{
    link_t *link = find_link(BLE_HS_CONN_HANDLE_NONE);
    if (link != NULL) {
        reset_link(link, conn_handle);
    }
}

void lab_stream_on_disconnect(uint16_t conn_handle)
{
    link_t *link = find_link(conn_handle);
    if (link == NULL) {
        return;
    }
    reset_link(link, BLE_HS_CONN_HANDLE_NONE);
    if (stream.state != STREAM_IDLE) {
        schedule_in(0);
    }
}

void lab_stream_on_subscribe(const struct ble_gap_event *event)
{
    link_t *link = find_link(event->subscribe.conn_handle);
    if (link == NULL) {
        return;
    }
    uint16_t handle = event->subscribe.attr_handle;
    if (handle == lab_gatt_stream_handle(LAB_STREAM_NOTIFY)) {
        link->subscribed[LAB_STREAM_NOTIFY] = event->subscribe.cur_notify;
    } else if (handle == lab_gatt_stream_handle(LAB_STREAM_INDICATE)) {
        link->subscribed[LAB_STREAM_INDICATE] = event->subscribe.cur_indicate;
    } else {
        return;
    }
    if (stream.state != STREAM_IDLE) {
        schedule_in(0);
    }
}

void lab_stream_on_notify_tx(const struct ble_gap_event *event)
{
    if (!event->notify_tx.indication || event->notify_tx.status == 0 ||
        event->notify_tx.attr_handle !=
            lab_gatt_stream_handle(LAB_STREAM_INDICATE)) {
        return;
    }
    link_t *link = find_link(event->notify_tx.conn_handle);
    if (link == NULL) {
        return;
    }
    link->awaiting_confirmation = false;
    if (stream.state != STREAM_IDLE) {
        schedule_in(0);
    }
}
