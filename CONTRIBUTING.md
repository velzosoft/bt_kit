# Contributing

Bug reports and pull requests are welcome. For a bug, include the phone model, the OS version and a log with `BtKit.logLevel = Level.FINE`.

## Building and testing

bt_kit needs Flutter 3.50 or later.

```sh
dart format lib test tool hook example/lib example/test example/integration_test
flutter analyze
flutter test
cd example && flutter analyze && flutter test
```

CI runs these checks on every pull request, together with release builds of the example for Android and iOS. Integration tests and the Lab run on phones; see [doc/testing.md](doc/testing.md) and [example/README.md](example/README.md#tests).

## Layer 1 bindings

Layer 1 and the Android callback adapters are generated. Every generated file says so in its first line; change the exposure rules in [`tool/`](tool/) instead of the output, then regenerate:

```sh
dart run tool/generate.dart
```

Regenerating needs the Android SDK platform `android-37.0`, Xcode with an iOS 26 or later SDK, and the Flutter SDK, whose Android embedding the hand-written Java classes compile against. Then check the result:

```sh
FLUTTER_JAR="$(dirname "$(which flutter)")/cache/artifacts/engine/android-arm/flutter.jar"
git diff --stat lib android src doc/inventory
flutter analyze
flutter test
javac --release 17 -Xlint:all -cp "$ANDROID_HOME/platforms/android-37.0/android.jar:$FLUTTER_JAR" $(find android/src -name '*.java')
xcrun --sdk iphoneos clang -c -fobjc-arc -target arm64-apple-ios18.0 src/ios/bindings.g.m
```

`flutter analyze` does not report compile errors inside the generated bindings, so always run `flutter test` as well. Without a rule change, regenerating must leave no diff.

## Pull requests

- Keep Layer 2 policy in platform-neutral code and cover it with unit tests on the fakes in [`test/fakes/`](test/fakes/).
- Record a new platform quirk in [doc/platform_notes.md](doc/platform_notes.md), with where Layer 2 handles it.
- Document public API with `///` comments; implementation code carries no `//` comments.
- Add an entry to [CHANGELOG.md](CHANGELOG.md) for any change users can see.

## Releasing

1. Set `version` in `pubspec.yaml` and add a section for it at the top of [CHANGELOG.md](CHANGELOG.md).
2. Commit and push, then publish and tag the release:

   ```sh
   flutter pub publish
   git tag v1.0.1
   git push origin v1.0.1
   ```
