#include <stdio.h>
#include <stdint.h>

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_err.h"
#include "esp_timer.h"

#include "onewire_bus.h"
#include "ds18b20.h"

// ===== KONFIGURASI SENSOR =====
#define ONE_WIRE_BUS 4  // DATA DS18B20 ke GPIO 4

#define DEVICE_DISCONNECTED_C -127.0f   // setara DallasTemperature
#define MAX_DS18B20 4

static onewire_bus_handle_t oneWire = NULL;
static ds18b20_device_handle_t sensors[MAX_DS18B20];
static int sensorCount = 0;

// ===== PARAMETER KALIBRASI =====
// Ganti sesuai hasil perbandingan dengan termometer referensi
float calibrationOffset = 0.0;

// Interval pembacaan
const unsigned long interval = 1000;
unsigned long previousMillis = 0;

// ---- Pengganti fungsi Arduino / DallasTemperature ----
static unsigned long millis(void) {
  return (unsigned long)(esp_timer_get_time() / 1000);
}

static void sensors_begin(void) {
  onewire_bus_config_t bus_config = {
    .bus_gpio_num = ONE_WIRE_BUS,
    .flags = { .en_pull_up = true },
  };
  onewire_bus_rmt_config_t rmt_config = {
    .max_rx_bytes = 10,
  };
  ESP_ERROR_CHECK(onewire_new_bus_rmt(&bus_config, &rmt_config, &oneWire));

  onewire_device_iter_handle_t iter = NULL;
  onewire_device_t next_device;
  esp_err_t search_result;

  ESP_ERROR_CHECK(onewire_new_device_iter(oneWire, &iter));
  do {
    search_result = onewire_device_iter_get_next(iter, &next_device);
    if (search_result == ESP_OK && sensorCount < MAX_DS18B20) {
      ds18b20_config_t ds_cfg = {};
      if (ds18b20_new_device_from_enumeration(&next_device, &ds_cfg, &sensors[sensorCount]) == ESP_OK) {
        sensorCount++;
      }
    }
  } while (search_result != ESP_ERR_NOT_FOUND);
  ESP_ERROR_CHECK(onewire_del_device_iter(iter));
}

static void sensors_setResolution(int bits) {
  (void)bits;  // 12 bit
  for (int i = 0; i < sensorCount; i++) {
    ds18b20_set_resolution(sensors[i], DS18B20_RESOLUTION_12B);
  }
}

static int sensors_getDeviceCount(void) {
  return sensorCount;
}

static void sensors_requestTemperatures(void) {
  if (sensorCount == 0) return;
  ds18b20_trigger_temperature_conversion_for_all(oneWire);
  vTaskDelay(pdMS_TO_TICKS(750));  // waktu konversi 12 bit (blocking seperti Arduino)
}

static float sensors_getTempCByIndex(int index) {
  float t;
  if (index >= sensorCount || ds18b20_get_temperature(sensors[index], &t) != ESP_OK) {
    return DEVICE_DISCONNECTED_C;
  }
  return t;
}

void setup(void) {
  // Baud rate console diatur di menuconfig (default 115200)
  vTaskDelay(pdMS_TO_TICKS(500));

  sensors_begin();
  sensors_setResolution(12);

  printf("\n=== ESP32 DS18B20 ===\n");
  printf("Pembacaan dan Kalibrasi Suhu\n");
  printf("--------------------------------\n");

  if (sensors_getDeviceCount() == 0) {
    printf("ERROR: DS18B20 tidak terdeteksi!\n");
    printf("Periksa wiring dan resistor pull-up.\n");
  } else {
    printf("Sensor terdeteksi: ");
    printf("%d\n", sensors_getDeviceCount());
  }
}

void loop(void) {
  unsigned long currentMillis = millis();

  if (currentMillis - previousMillis >= interval) {
    previousMillis = currentMillis;

    sensors_requestTemperatures();

    float rawTemp = sensors_getTempCByIndex(0);

    // Validasi komunikasi sensor
    if (rawTemp == DEVICE_DISCONNECTED_C) {
      printf("ERROR: Gagal membaca sensor.\n");
      return;
    }

    // Validasi rentang fisik sensor DS18B20
    if (rawTemp < -55.0 || rawTemp > 125.0) {
      printf("ERROR: Pembacaan suhu di luar rentang.\n");
      return;
    }

    // Koreksi suhu menggunakan offset
    float calibratedTemp = rawTemp + calibrationOffset;

    printf("Suhu aktual sensor : ");
    printf("%.2f", rawTemp);
    printf(" °C\n");

    printf("Offset kalibrasi   : ");
    printf("%.2f", calibrationOffset);
    printf(" °C\n");

    printf("Suhu terkoreksi    : ");
    printf("%.2f", calibratedTemp);
    printf(" °C\n");

    printf("--------------------------------\n");
  }
}

void app_main(void) {
  setup();
  while (1) {
    loop();
    vTaskDelay(pdMS_TO_TICKS(10));  // beri waktu ke task lain / watchdog
  }
}
