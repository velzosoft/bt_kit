idf_component_register(
    SRCS
        "main.c"
        "board_button.c"
        "board_gatt.c"
        "board_led.c"
        "board_led_driver.c"
        "board_ramp.c"
    INCLUDE_DIRS "."
    PRIV_REQUIRES
        bt
        nvs_flash
        esp_timer
        esp_app_format
        esp_driver_gpio
        esp_driver_ledc
)
