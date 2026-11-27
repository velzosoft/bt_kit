#include "board_led_driver.h"

#include <math.h>
#include <stdbool.h>

#include "sdkconfig.h"

#if CONFIG_BOARD_LED_KIND_ADDRESSABLE
#include "led_strip.h"
#else
#include "driver/ledc.h"
#endif

#define GAMMA 2.2f
#define LEVELS 256

static float output[LEVELS];
static board_color_t shown;
static bool has_shown;

static void build_output_curve(void)
{
    for (int level = 0; level < LEVELS; level++) {
        output[level] = powf(level / 255.0f, GAMMA) *
                        CONFIG_BOARD_LED_BRIGHTNESS / 255.0f;
    }
}

#if CONFIG_BOARD_LED_KIND_ADDRESSABLE

#define RMT_RESOLUTION_HZ (10 * 1000 * 1000)

static led_strip_handle_t strip;

static esp_err_t init_led(void)
{
    led_strip_config_t strip_config = {
        .strip_gpio_num = CONFIG_BOARD_LED_GPIO,
        .max_leds = 1,
        .led_model = LED_MODEL_WS2812,
        .color_component_format = LED_STRIP_COLOR_COMPONENT_FMT_GRB,
    };
    led_strip_rmt_config_t rmt_config = {
        .resolution_hz = RMT_RESOLUTION_HZ,
    };
    esp_err_t rc = led_strip_new_rmt_device(&strip_config, &rmt_config, &strip);
    if (rc != ESP_OK) {
        return rc;
    }
    return led_strip_clear(strip);
}

static uint32_t to_pixel(uint8_t level)
{
    return (uint32_t)lroundf(output[level] * 255.0f);
}

static void show(board_color_t color)
{
    led_strip_set_pixel(strip, 0, to_pixel(color.red), to_pixel(color.green),
                        to_pixel(color.blue));
    led_strip_refresh(strip);
}

board_led_kind_t board_led_driver_kind(void)
{
    return BOARD_LED_ADDRESSABLE;
}

#else

#define PWM_MODE LEDC_LOW_SPEED_MODE
#define PWM_TIMER LEDC_TIMER_0
#define PWM_RESOLUTION LEDC_TIMER_13_BIT
#define PWM_MAX_DUTY ((1u << 13) - 1)
#define PWM_FREQUENCY_HZ 5000

#if CONFIG_BOARD_LED_KIND_RGB
#define CHANNELS 3
static const int pins[CHANNELS] = {
    CONFIG_BOARD_RGB_GPIO_RED,
    CONFIG_BOARD_RGB_GPIO_GREEN,
    CONFIG_BOARD_RGB_GPIO_BLUE,
};
#else
#define CHANNELS 1
static const int pins[CHANNELS] = {CONFIG_BOARD_LED_GPIO};
#endif

#if CONFIG_BOARD_RGB_COMMON_ANODE || CONFIG_BOARD_LED_ACTIVE_LOW
#define PWM_INVERTED 1
#else
#define PWM_INVERTED 0
#endif

static esp_err_t init_led(void)
{
    ledc_timer_config_t timer = {
        .speed_mode = PWM_MODE,
        .duty_resolution = PWM_RESOLUTION,
        .timer_num = PWM_TIMER,
        .freq_hz = PWM_FREQUENCY_HZ,
        .clk_cfg = LEDC_AUTO_CLK,
    };
    esp_err_t rc = ledc_timer_config(&timer);
    for (int channel = 0; channel < CHANNELS && rc == ESP_OK; channel++) {
        ledc_channel_config_t config = {
            .gpio_num = pins[channel],
            .speed_mode = PWM_MODE,
            .channel = (ledc_channel_t)channel,
            .timer_sel = PWM_TIMER,
            .duty = 0,
            .hpoint = 0,
            .flags.output_invert = PWM_INVERTED,
        };
        rc = ledc_channel_config(&config);
    }
    return rc;
}

static void set_level(int channel, uint8_t level)
{
    uint32_t duty = (uint32_t)lroundf(output[level] * PWM_MAX_DUTY);
    ledc_set_duty(PWM_MODE, (ledc_channel_t)channel, duty);
    ledc_update_duty(PWM_MODE, (ledc_channel_t)channel);
}

#if CONFIG_BOARD_LED_KIND_RGB

static void show(board_color_t color)
{
    set_level(0, color.red);
    set_level(1, color.green);
    set_level(2, color.blue);
}

board_led_kind_t board_led_driver_kind(void)
{
    return BOARD_LED_RGB;
}

#else

static uint8_t brightest(board_color_t color)
{
    uint8_t level = color.red > color.green ? color.red : color.green;
    return level > color.blue ? level : color.blue;
}

static void show(board_color_t color)
{
    set_level(0, brightest(color));
}

board_led_kind_t board_led_driver_kind(void)
{
    return BOARD_LED_SINGLE;
}

#endif

#endif

esp_err_t board_led_driver_init(void)
{
    build_output_curve();
    return init_led();
}

void board_led_driver_show(board_color_t color)
{
    if (has_shown && color.red == shown.red && color.green == shown.green &&
        color.blue == shown.blue) {
        return;
    }
    shown = color;
    has_shown = true;
    show(color);
}
