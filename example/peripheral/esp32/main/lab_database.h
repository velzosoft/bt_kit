#pragma once

#include <stdint.h>

#include "os/os_mbuf.h"

void lab_database_init(void);

int lab_database_command(const uint8_t *data, uint16_t length);

int lab_database_append_state(struct os_mbuf *om);
