package dev.btkit;

import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import io.flutter.FlutterInjector;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.embedding.engine.loader.FlutterLoader;
import io.flutter.view.FlutterCallbackInformation;
import java.util.ArrayDeque;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Hands events the system delivers in the background to Dart: to the engine that listened last,
 * or, while none listens, to a headless engine that runs the app's registered handler.
 *
 * <p>A broadcast receiver's process may be frozen once {@code onReceive} returns, so each scan
 * result keeps its receiver alive until Dart has handled it, for at most {@link #HOLD_LIMIT_MS}.
 * Only listeners that acknowledge events with {@link #handled} keep it that long, which the
 * headless engine does; for any other listener the receiver finishes at once.
 */
public final class BackgroundDelivery {
  public interface Listener {
    void onEvent(Intent event);
  }

  public static final String ACTION_SCAN_RESULT = "dev.btkit.action.SCAN_RESULT";
  public static final String ACTION_PRESENCE = "dev.btkit.action.PRESENCE";
  public static final String EXTRA_ASSOCIATION_ID = "dev.btkit.extra.ASSOCIATION_ID";

  /** A {@code DevicePresenceEvent} constant; API 33 to 35 report only appearing and leaving. */
  public static final String EXTRA_PRESENCE = "dev.btkit.extra.PRESENCE";

  private static final String PREFERENCES = "dev.btkit.background";
  private static final String KEY_DISPATCHER = "dispatcher";
  private static final String KEY_HANDLER = "handler";
  private static final long HOLD_LIMIT_MS = 9000;
  private static final int PENDING_LIMIT = 64;

  private static final class Registration {
    final Listener listener;
    final boolean acknowledges;

    Registration(Listener listener, boolean acknowledges) {
      this.listener = listener;
      this.acknowledges = acknowledges;
    }
  }

  private static final class Delivery {
    final Intent event;
    final BroadcastReceiver.PendingResult hold;
    boolean finished;

    Delivery(Intent event, BroadcastReceiver.PendingResult hold) {
      this.event = event;
      this.hold = hold;
    }
  }

  private static final Map<Long, Registration> listeners = new LinkedHashMap<>();
  private static final ArrayDeque<Delivery> pending = new ArrayDeque<>();
  private static final ArrayDeque<Delivery> awaiting = new ArrayDeque<>();
  private static final Handler main = new Handler(Looper.getMainLooper());
  private static FlutterEngine headless;

  private BackgroundDelivery() {}

  /**
   * Makes {@code listener} the receiver of every event, including those still pending. With
   * {@code acknowledges}, it calls {@link #handled} once for each event, in order.
   */
  public static synchronized void setListener(
      long engineId, Listener listener, boolean acknowledges) {
    Registration registration = new Registration(listener, acknowledges);
    listeners.remove(engineId);
    listeners.put(engineId, registration);
    while (!pending.isEmpty()) send(registration, pending.removeFirst());
  }

  public static synchronized void removeListener(long engineId) {
    listeners.remove(engineId);
  }

  /** Stores the Dart callbacks the headless engine runs: bt_kit's dispatcher and the app's handler. */
  public static void setHandles(Context context, long dispatcher, long handler) {
    preferences(context).edit().putLong(KEY_DISPATCHER, dispatcher).putLong(KEY_HANDLER, handler).apply();
  }

  public static long handler(Context context) {
    return preferences(context).getLong(KEY_HANDLER, 0);
  }

  /** The intent the system sends scan results to, through {@link BackgroundScanReceiver}. */
  public static PendingIntent scanIntent(Context context) {
    Intent intent = new Intent(context, BackgroundScanReceiver.class).setAction(ACTION_SCAN_RESULT);
    return PendingIntent.getBroadcast(
        context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_MUTABLE);
  }

  /** The oldest event sent to an acknowledging listener has been handled. */
  public static synchronized void handled() {
    Delivery delivery = awaiting.pollFirst();
    if (delivery != null) finish(delivery);
  }

  static synchronized void deliver(
      Context context, Intent event, BroadcastReceiver.PendingResult hold) {
    Delivery delivery = new Delivery(event, hold);
    if (hold != null) main.postDelayed(() -> finish(delivery), HOLD_LIMIT_MS);
    Registration registration = null;
    for (Registration candidate : listeners.values()) registration = candidate;
    if (registration != null) {
      send(registration, delivery);
      return;
    }
    if (!startHeadless(context.getApplicationContext())) {
      finish(delivery);
      return;
    }
    if (pending.size() >= PENDING_LIMIT) finish(pending.removeFirst());
    pending.add(delivery);
  }

  private static void send(Registration registration, Delivery delivery) {
    registration.listener.onEvent(delivery.event);
    if (registration.acknowledges) {
      awaiting.add(delivery);
    } else {
      finish(delivery);
    }
  }

  private static synchronized void finish(Delivery delivery) {
    if (delivery.finished) return;
    delivery.finished = true;
    if (delivery.hold != null) delivery.hold.finish();
  }

  /**
   * Starts the headless engine unless it runs; returns whether it does. The callback cache is
   * only readable once Flutter is initialized.
   */
  private static boolean startHeadless(Context context) {
    if (headless != null) return true;
    long dispatcher = preferences(context).getLong(KEY_DISPATCHER, 0);
    if (dispatcher == 0) return false;
    FlutterLoader loader = FlutterInjector.instance().flutterLoader();
    loader.startInitialization(context);
    loader.ensureInitializationComplete(context, null);
    FlutterCallbackInformation callback =
        FlutterCallbackInformation.lookupCallbackInformation(dispatcher);
    if (callback == null) return false;
    headless = new FlutterEngine(context);
    headless
        .getDartExecutor()
        .executeDartCallback(
            new DartExecutor.DartCallback(
                context.getAssets(), loader.findAppBundlePath(), callback));
    return true;
  }

  private static SharedPreferences preferences(Context context) {
    return context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE);
  }
}
