#pragma once

#include <stdint.h>

#include "board_profile.h"

float board_ramp_hue(int64_t held_us);

float board_ramp_brightness(int64_t held_us);

board_color_t board_ramp_color(int64_t held_us);

board_color_t board_hsv_to_rgb(float hue, float saturation, float value);
