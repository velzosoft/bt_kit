package dev.btkit;

import android.companion.AssociationInfo;
import android.companion.CompanionDeviceService;
import android.companion.DevicePresenceEvent;
import android.content.Intent;
import android.os.Build;

/**
 * Reports the presence of associated companion devices to Dart, even while the app is not
 * running. Apps that observe presence through bt_kit declare it in their manifest.
 */
public final class CompanionPresenceService extends CompanionDeviceService {
  private static final int PRESENCE_API = 36;

  @Override
  public void onDevicePresenceEvent(DevicePresenceEvent event) {
    deliver(event.getAssociationId(), event.getEvent());
  }

  @Override
  @SuppressWarnings("deprecation")
  public void onDeviceAppeared(AssociationInfo associationInfo) {
    if (Build.VERSION.SDK_INT < PRESENCE_API) {
      deliver(associationInfo.getId(), DevicePresenceEvent.EVENT_BLE_APPEARED);
    }
  }

  @Override
  @SuppressWarnings("deprecation")
  public void onDeviceDisappeared(AssociationInfo associationInfo) {
    if (Build.VERSION.SDK_INT < PRESENCE_API) {
      deliver(associationInfo.getId(), DevicePresenceEvent.EVENT_BLE_DISAPPEARED);
    }
  }

  private void deliver(int associationId, int presence) {
    Intent event =
        new Intent(BackgroundDelivery.ACTION_PRESENCE)
            .putExtra(BackgroundDelivery.EXTRA_ASSOCIATION_ID, associationId)
            .putExtra(BackgroundDelivery.EXTRA_PRESENCE, presence);
    BackgroundDelivery.deliver(this, event, null);
  }
}
