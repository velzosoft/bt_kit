package dev.btkit;

import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanFilter;
import android.bluetooth.le.ScanSettings;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Starts and stops scans on one background thread, in the order they are asked for.
 *
 * <p>{@link BluetoothLeScanner#startScan(List, ScanSettings, ScanCallback)} blocks its caller until
 * the scanner is registered, and reports {@link
 * ScanCallback#SCAN_FAILED_APPLICATION_REGISTRATION_FAILED} when that wait wakes early. Signals
 * wake it, and Dart threads receive them, so scans start here instead.
 */
public final class ScanThread {
  public interface Listener {
    void onStartFailed(boolean permissionDenied, String message);
  }

  private static final ExecutorService executor =
      Executors.newSingleThreadExecutor(
          task -> {
            Thread thread = new Thread(task, "bt_kit scans");
            thread.setDaemon(true);
            return thread;
          });

  private ScanThread() {}

  public static void startScan(
      BluetoothLeScanner scanner,
      List<ScanFilter> filters,
      ScanSettings settings,
      ScanCallback callback,
      Listener listener) {
    executor.execute(
        () -> {
          try {
            scanner.startScan(filters, settings, callback);
          } catch (RuntimeException e) {
            listener.onStartFailed(e instanceof SecurityException, e.toString());
          }
        });
  }

  public static void stopScan(BluetoothLeScanner scanner, ScanCallback callback) {
    executor.execute(
        () -> {
          try {
            scanner.stopScan(callback);
          } catch (RuntimeException ignored) {
          }
        });
  }
}
