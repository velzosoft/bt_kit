# Dart reaches these classes through JNI only, so R8 cannot see their uses.
-keep class dev.btkit.** { *; }

# The adapters reference Bluetooth classes newer than the app's compileSdk
# may know. They exist on every device that can call them.
-dontwarn android.bluetooth.**
-dontwarn android.companion.**
-dontwarn android.ranging.**
