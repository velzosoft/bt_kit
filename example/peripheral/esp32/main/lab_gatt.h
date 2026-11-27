#pragma once

#include <stdint.h>

#include "lab_profile.h"

int lab_gatt_init(void);

uint16_t lab_gatt_stream_handle(lab_stream_kind_t kind);
