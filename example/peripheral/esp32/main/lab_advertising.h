#pragma once

#include <stdint.h>

#include "host/ble_gap.h"

int lab_advertising_configure(uint8_t own_addr_type, ble_gap_event_fn *on_event);

void lab_advertising_start(void);
