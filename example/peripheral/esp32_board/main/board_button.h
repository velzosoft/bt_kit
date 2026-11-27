#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

typedef void board_button_handler_t(bool pressed, int64_t at_us);

esp_err_t board_button_init(board_button_handler_t *on_change);
