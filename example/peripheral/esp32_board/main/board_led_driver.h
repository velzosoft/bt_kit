#pragma once

#include "esp_err.h"

#include "board_profile.h"

esp_err_t board_led_driver_init(void);

board_led_kind_t board_led_driver_kind(void);

void board_led_driver_show(board_color_t color);
