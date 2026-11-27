#include "board_led.h"

#include <math.h>

#include "board_led_driver.h"
#include "board_ramp.h"

#define MS_US 1000
#define SLOW_BLINK_ON_US (100 * MS_US)
#define SLOW_BLINK_PERIOD_US (1000 * MS_US)
#define FAST_BLINK_ON_US (125 * MS_US)
#define FAST_BLINK_PERIOD_US (250 * MS_US)
#define FLASH_ON_US (150 * MS_US)
#define FLASH_PERIOD_US (300 * MS_US)

#define BLACK {0x00, 0x00, 0x00}
#define WHITE {0xff, 0xff, 0xff}
#define BLUE {0x00, 0x00, 0xff}
#define AMBER {0xff, 0x90, 0x00}
#define GREEN {0x00, 0xff, 0x00}
#define RED {0xff, 0x00, 0x00}

typedef struct {
    board_pattern_t pattern;
    board_color_t color;
} look_t;

static const look_t state_looks[BOARD_STATES] = {
    [BOARD_STATE_STARTING] = {BOARD_PATTERN_SOLID, WHITE},
    [BOARD_STATE_WAITING] = {BOARD_PATTERN_SLOW_BLINK, BLUE},
    [BOARD_STATE_CONNECTED] = {BOARD_PATTERN_FAST_BLINK, AMBER},
    [BOARD_STATE_READY] = {BOARD_PATTERN_SOLID, GREEN},
    [BOARD_STATE_ERROR] = {BOARD_PATTERN_FAST_BLINK, RED},
};

static const board_color_t black = BLACK;

static struct {
    board_led_kind_t kind;
    board_state_t state;
    bool flashing;
    bool flash_restarted;
    board_color_t flash_color;
    uint8_t flash_count;
    int64_t flash_start_us;
    bool held;
    int64_t hold_start_us;
    board_led_value_t shown;
    int64_t shown_since_us;
} led;

static bool same_color(board_color_t a, board_color_t b)
{
    return a.red == b.red && a.green == b.green && a.blue == b.blue;
}

static bool same_value(const board_led_value_t *a, const board_led_value_t *b)
{
    return a->state == b->state && a->pattern == b->pattern &&
           same_color(a->color, b->color) && a->flashes == b->flashes;
}

static board_led_value_t current_value(void)
{
    if (led.flashing) {
        return (board_led_value_t){
            led.state,
            BOARD_PATTERN_FLASHES,
            led.flash_color,
            led.flash_count,
        };
    }
    if (led.held) {
        return (board_led_value_t){
            led.state,
            BOARD_PATTERN_HOLD_RAMP,
            board_ramp_color(0),
            0,
        };
    }
    look_t look = state_looks[led.state];
    return (board_led_value_t){led.state, look.pattern, look.color, 0};
}

void board_led_init(board_led_kind_t kind, int64_t now_us)
{
    led.kind = kind;
    led.state = BOARD_STATE_STARTING;
    led.shown = current_value();
    led.shown_since_us = now_us;
}

board_state_t board_led_state(void)
{
    return led.state;
}

void board_led_set_state(board_state_t state)
{
    led.state = state;
}

void board_led_flash(board_color_t color, uint8_t count, int64_t now_us)
{
    led.flashing = true;
    led.flash_restarted = true;
    led.flash_color = color;
    led.flash_count = count;
    led.flash_start_us = now_us;
}

void board_led_stop_flashing(void)
{
    led.flashing = false;
}

void board_led_hold(bool held, int64_t now_us)
{
    led.held = held;
    led.hold_start_us = now_us;
}

bool board_led_refresh(int64_t now_us, board_led_value_t *value)
{
    if (led.flashing &&
        now_us - led.flash_start_us >= led.flash_count * FLASH_PERIOD_US) {
        led.flashing = false;
    }
    board_led_value_t next = current_value();
    bool changed = led.flash_restarted || !same_value(&next, &led.shown);
    if (changed) {
        led.shown = next;
        led.shown_since_us = now_us;
        led.flash_restarted = false;
    }
    *value = led.shown;
    return changed;
}

static board_color_t blink(int64_t elapsed_us, int64_t on_us, int64_t period_us,
                           board_color_t color)
{
    return elapsed_us % period_us < on_us ? color : black;
}

static board_color_t hold_color(int64_t held_us)
{
    if (led.kind != BOARD_LED_SINGLE) {
        return board_ramp_color(held_us);
    }
    uint8_t level = (uint8_t)lroundf(board_ramp_brightness(held_us) * 255.0f);
    return (board_color_t){level, level, level};
}

static board_color_t color_at(int64_t now_us)
{
    int64_t elapsed_us = now_us - led.shown_since_us;
    board_color_t color = led.shown.color;
    switch (led.shown.pattern) {
    case BOARD_PATTERN_SOLID:
        return color;
    case BOARD_PATTERN_SLOW_BLINK:
        return blink(elapsed_us, SLOW_BLINK_ON_US, SLOW_BLINK_PERIOD_US, color);
    case BOARD_PATTERN_FAST_BLINK:
        return blink(elapsed_us, FAST_BLINK_ON_US, FAST_BLINK_PERIOD_US, color);
    case BOARD_PATTERN_FLASHES:
        return blink(now_us - led.flash_start_us, FLASH_ON_US, FLASH_PERIOD_US,
                     color);
    case BOARD_PATTERN_HOLD_RAMP:
        return hold_color(now_us - led.hold_start_us);
    default:
        return black;
    }
}

void board_led_render(int64_t now_us)
{
    board_led_driver_show(color_at(now_us));
}
