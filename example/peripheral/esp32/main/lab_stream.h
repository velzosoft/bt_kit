#pragma once

#include <stdint.h>

#include "host/ble_gap.h"
#include "os/os_mbuf.h"

void lab_stream_init(void);

int lab_stream_command(const uint8_t *data, uint16_t length);

int lab_stream_append_command(struct os_mbuf *om);

void lab_stream_on_connect(uint16_t conn_handle);

void lab_stream_on_disconnect(uint16_t conn_handle);

void lab_stream_on_subscribe(const struct ble_gap_event *event);

void lab_stream_on_notify_tx(const struct ble_gap_event *event);
