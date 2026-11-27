#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "board_profile.h"

typedef bool board_command_handler_t(const board_command_t *command);

int board_gatt_init(board_led_kind_t kind, board_command_handler_t *on_command);

uint16_t board_gatt_button_handle(void);

void board_gatt_connected(uint16_t conn_handle);

void board_gatt_disconnected(void);

void board_gatt_subscription(uint16_t attr_handle, bool notify);

void board_gatt_publish_button(const board_button_value_t *value,
                               int64_t pressed_at_us);

void board_gatt_publish_led(const board_led_value_t *value);
