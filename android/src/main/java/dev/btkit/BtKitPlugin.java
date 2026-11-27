package dev.btkit;

import android.content.Intent;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.PluginRegistry;

/** Connects {@link ActivityBridge} to the activity of each Flutter engine. */
public final class BtKitPlugin
    implements FlutterPlugin,
        ActivityAware,
        PluginRegistry.RequestPermissionsResultListener,
        PluginRegistry.ActivityResultListener {
  private ActivityBridge bridge;
  private long engineId;
  private ActivityPluginBinding binding;

  @Override
  @SuppressWarnings("deprecation")
  public void onAttachedToEngine(FlutterPluginBinding binding) {
    engineId = binding.getFlutterEngine().getEngineId();
    bridge = ActivityBridge.of(engineId);
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {
    ActivityBridge.remove(engineId);
    BackgroundDelivery.removeListener(engineId);
    bridge = null;
  }

  @Override
  public void onAttachedToActivity(ActivityPluginBinding binding) {
    this.binding = binding;
    binding.addRequestPermissionsResultListener(this);
    binding.addActivityResultListener(this);
    bridge.attach(binding.getActivity());
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    onDetachedFromActivity();
  }

  @Override
  public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
    onAttachedToActivity(binding);
  }

  @Override
  public void onDetachedFromActivity() {
    if (binding != null) {
      binding.removeRequestPermissionsResultListener(this);
      binding.removeActivityResultListener(this);
      binding = null;
    }
    if (bridge != null) bridge.attach(null);
  }

  @Override
  public boolean onRequestPermissionsResult(
      int requestCode, String[] permissions, int[] grantResults) {
    return bridge != null && bridge.deliverPermissions(requestCode, permissions, grantResults);
  }

  @Override
  public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
    return bridge != null && bridge.deliverActivityResult(requestCode, resultCode, data);
  }
}
