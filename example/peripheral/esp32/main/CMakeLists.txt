idf_component_register(
    SRCS
        "main.c"
        "lab_advertising.c"
        "lab_database.c"
        "lab_gatt.c"
        "lab_stream.c"
    INCLUDE_DIRS "."
    PRIV_REQUIRES bt nvs_flash esp_timer esp_app_format
)
