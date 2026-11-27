#include "board_button.h"

#include "driver/gpio.h"
#include "esp_timer.h"
#include "sdkconfig.h"

#define POLL_US 10000
#define DEBOUNCE_US 30000

#if CONFIG_BOARD_BUTTON_ACTIVE_LOW
#define PRESSED_LEVEL 0
#else
#define PRESSED_LEVEL 1
#endif

static board_button_handler_t *handler;
static esp_timer_handle_t timer;
static bool pressed;
static bool candidate;
static int64_t candidate_since_us;

static void poll(void *arg)
{
    int64_t now_us = esp_timer_get_time();
    bool level_pressed =
        gpio_get_level(CONFIG_BOARD_BUTTON_GPIO) == PRESSED_LEVEL;
    if (level_pressed == pressed) {
        candidate = pressed;
        return;
    }
    if (level_pressed != candidate) {
        candidate = level_pressed;
        candidate_since_us = now_us;
        return;
    }
    if (now_us - candidate_since_us >= DEBOUNCE_US) {
        pressed = level_pressed;
        handler(pressed, candidate_since_us);
    }
}

esp_err_t board_button_init(board_button_handler_t *on_change)
{
    handler = on_change;
    gpio_config_t config = {
        .pin_bit_mask = 1ULL << CONFIG_BOARD_BUTTON_GPIO,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = PRESSED_LEVEL == 0 ? GPIO_PULLUP_ENABLE
                                         : GPIO_PULLUP_DISABLE,
        .pull_down_en = PRESSED_LEVEL == 1 ? GPIO_PULLDOWN_ENABLE
                                           : GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    esp_err_t rc = gpio_config(&config);
    if (rc != ESP_OK) {
        return rc;
    }
    const esp_timer_create_args_t args = {
        .callback = poll,
        .name = "board_button",
    };
    rc = esp_timer_create(&args, &timer);
    if (rc != ESP_OK) {
        return rc;
    }
    return esp_timer_start_periodic(timer, POLL_US);
}
