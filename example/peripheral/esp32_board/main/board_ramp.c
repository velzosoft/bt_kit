#include "board_ramp.h"

#include <math.h>

#define START_HUE 120.0f
#define DEGREES_PER_SECOND 42.0f
#define RAMP_SECONDS 5.0f
#define MIN_BRIGHTNESS 0.2f

static float ramp_seconds(int64_t held_us)
{
    float seconds = held_us / 1e6f;
    if (seconds < 0) {
        return 0;
    }
    return seconds < RAMP_SECONDS ? seconds : RAMP_SECONDS;
}

float board_ramp_hue(int64_t held_us)
{
    float hue =
        fmodf(START_HUE - DEGREES_PER_SECOND * ramp_seconds(held_us), 360.0f);
    return hue < 0 ? hue + 360.0f : hue;
}

float board_ramp_brightness(int64_t held_us)
{
    return MIN_BRIGHTNESS +
           (1.0f - MIN_BRIGHTNESS) * ramp_seconds(held_us) / RAMP_SECONDS;
}

board_color_t board_ramp_color(int64_t held_us)
{
    return board_hsv_to_rgb(board_ramp_hue(held_us), 1.0f, 1.0f);
}

static uint8_t to_channel(float value)
{
    return (uint8_t)lroundf(value * 255.0f);
}

board_color_t board_hsv_to_rgb(float hue, float saturation, float value)
{
    float chroma = value * saturation;
    float sector = fmodf(hue, 360.0f) / 60.0f;
    float secondary = chroma * (1.0f - fabsf(fmodf(sector, 2.0f) - 1.0f));
    float match = value - chroma;
    float red = 0;
    float green = 0;
    float blue = 0;
    switch ((int)sector) {
    case 0:
        red = chroma;
        green = secondary;
        break;
    case 1:
        red = secondary;
        green = chroma;
        break;
    case 2:
        green = chroma;
        blue = secondary;
        break;
    case 3:
        green = secondary;
        blue = chroma;
        break;
    case 4:
        red = secondary;
        blue = chroma;
        break;
    default:
        red = chroma;
        blue = secondary;
        break;
    }
    return (board_color_t){
        to_channel(red + match),
        to_channel(green + match),
        to_channel(blue + match),
    };
}
