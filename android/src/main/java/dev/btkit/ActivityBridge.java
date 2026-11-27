package dev.btkit;

import android.app.Activity;
import android.content.Intent;
import android.content.IntentSender;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/** Lets Dart start activities and receive their results for one Flutter engine. */
public final class ActivityBridge {
  public interface Listener {
    void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults);

    void onActivityResult(int requestCode, int resultCode, Intent data);
  }

  /** Request codes from this range belong to bt_kit. */
  public static final int FIRST_REQUEST_CODE = 0xB700;

  public static final int LAST_REQUEST_CODE = 0xB7FF;

  private static final Map<Long, ActivityBridge> bridges = new ConcurrentHashMap<>();

  private volatile Activity activity;
  private volatile Listener listener;

  private ActivityBridge() {}

  public static void setListener(long engineId, Listener listener) {
    of(engineId).listener = listener;
  }

  public static boolean hasActivity(long engineId) {
    return of(engineId).activity != null;
  }

  public static boolean requestPermissions(long engineId, String[] permissions, int requestCode) {
    Activity activity = of(engineId).activity;
    if (activity == null) return false;
    activity.requestPermissions(permissions, requestCode);
    return true;
  }

  public static boolean shouldShowRequestPermissionRationale(long engineId, String permission) {
    Activity activity = of(engineId).activity;
    return activity != null && activity.shouldShowRequestPermissionRationale(permission);
  }

  public static boolean startActivityForResult(long engineId, Intent intent, int requestCode) {
    Activity activity = of(engineId).activity;
    if (activity == null) return false;
    activity.startActivityForResult(intent, requestCode);
    return true;
  }

  public static boolean startIntentSenderForResult(
      long engineId, IntentSender sender, int requestCode) {
    Activity activity = of(engineId).activity;
    if (activity == null) return false;
    try {
      activity.startIntentSenderForResult(sender, requestCode, null, 0, 0, 0);
      return true;
    } catch (IntentSender.SendIntentException e) {
      return false;
    }
  }

  private static boolean owns(int requestCode) {
    return requestCode >= FIRST_REQUEST_CODE && requestCode <= LAST_REQUEST_CODE;
  }

  static ActivityBridge of(long engineId) {
    return bridges.computeIfAbsent(engineId, id -> new ActivityBridge());
  }

  static void remove(long engineId) {
    bridges.remove(engineId);
  }

  void attach(Activity activity) {
    this.activity = activity;
  }

  boolean deliverPermissions(int requestCode, String[] permissions, int[] grantResults) {
    Listener listener = this.listener;
    if (listener == null || !owns(requestCode)) return false;
    listener.onRequestPermissionsResult(requestCode, permissions, grantResults);
    return true;
  }

  boolean deliverActivityResult(int requestCode, int resultCode, Intent data) {
    Listener listener = this.listener;
    if (listener == null || !owns(requestCode)) return false;
    listener.onActivityResult(requestCode, resultCode, data);
    return true;
  }
}
