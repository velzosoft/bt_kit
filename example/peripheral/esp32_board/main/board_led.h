#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "board_profile.h"

void board_led_init(board_led_kind_t kind, int64_t now_us);

board_state_t board_led_state(void);

void board_led_set_state(board_state_t state);

void board_led_flash(board_color_t color, uint8_t count, int64_t now_us);

void board_led_stop_flashing(void);

void board_led_hold(bool held, int64_t now_us);

bool board_led_refresh(int64_t now_us, board_led_value_t *value);

void board_led_render(int64_t now_us);
