/// The Layer 1 object behind a Layer 2 object.
///
/// [A] is the Android type and [I] the iOS type. Use [android] and [ios] to
/// reach the platform API directly, or switch over the subtypes:
///
/// ```dart
/// switch (characteristic.native) {
///   case AndroidHandle(:final value): value.instanceId;
///   case IosHandle(:final value): value.isNotifying;
/// }
/// ```
sealed class NativeHandle<A extends Object, I extends Object> {
  const NativeHandle();

  /// The Android object, or null on iOS.
  A? get android;

  /// The iOS object, or null on Android.
  I? get ios;
}

final class AndroidHandle<A extends Object, I extends Object>
    extends NativeHandle<A, I> {
  const AndroidHandle(this.value);

  final A value;

  @override
  A get android => value;

  @override
  I? get ios => null;
}

final class IosHandle<A extends Object, I extends Object>
    extends NativeHandle<A, I> {
  const IosHandle(this.value);

  final I value;

  @override
  A? get android => null;

  @override
  I get ios => value;
}
