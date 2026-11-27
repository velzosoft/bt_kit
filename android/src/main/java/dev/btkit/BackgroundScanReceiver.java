package dev.btkit;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Receives the results of scans started with {@link BackgroundDelivery#scanIntent}. */
public final class BackgroundScanReceiver extends BroadcastReceiver {
  @Override
  public void onReceive(Context context, Intent intent) {
    BackgroundDelivery.deliver(context, intent, goAsync());
  }
}
