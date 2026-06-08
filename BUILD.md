# Building BrickLogic for the Google Play Store

BrickLogic ships to Play as an **Android App Bundle** (`.aab`). This is a
one-time keystore setup, then a single command per release.

- **Application ID:** `dev.perpaterb.bricklogic` (permanent — set in
  `android/app/build.gradle.kts`)
- **Version:** set by `version:` in `pubspec.yaml`, e.g. `1.0.0+1`
  (`1.0.0` is the versionName shown to users; `+1` is the versionCode Play
  uses to order builds — it must increase every upload).

## One-time setup: create the upload keystore

The keystore signs every release. **Keep it and its passwords safe and
backed up** — if you lose it you can't update the app on Play (you'd have to
publish a new listing). It is never committed to git.

1. Pick a folder outside the repo, e.g. `~/keys`, and create the key. Choose
   a strong password when prompted (you'll reuse it below):

   ```sh
   mkdir -p ~/keys
   keytool -genkey -v \
     -keystore ~/keys/bricklogic-upload.jks \
     -keyalg RSA -keysize 2048 -validity 10000 \
     -alias upload
   ```

   It asks for a keystore password and some name/organisation fields (any
   sensible answers are fine). When it asks for the *key* password, pressing
   Enter reuses the keystore password — simplest.

2. Tell the build where the keystore is and its passwords. Copy the example
   and fill it in:

   ```sh
   cp android/key.properties.example android/key.properties
   ```

   Edit `android/key.properties`:

   ```properties
   storePassword=<the keystore password you chose>
   keyPassword=<the key password, same as above if you pressed Enter>
   keyAlias=upload
   storeFile=/home/bob/keys/bricklogic-upload.jks
   ```

   `android/key.properties`, `*.jks` and `*.keystore` are git-ignored — they
   must never be committed.

## Each release

1. Bump the version in `pubspec.yaml`. The `+N` build number **must** go up
   every time you upload to Play:

   ```yaml
   version: 1.0.1+2
   ```

2. Build the signed bundle:

   ```sh
   ./scripts/build_release.sh
   ```

   This runs `flutter build appbundle --release` and copies the result to
   `releases/bricklogic-<version>-<build>.aab`
   (e.g. `releases/bricklogic-1.0.1-2.aab`). The `.aab` files are git-ignored.

3. Upload that `.aab` in the [Play Console](https://play.google.com/console)
   → your app → **Production** (or a testing track) → **Create new release**.
   First time only: opt in to **Play App Signing** (recommended) — Play keeps
   the app signing key and your keystore above is the *upload* key.

## Testing the release build locally

You don't need the Play Store to test the release build on a plugged-in
device:

```sh
flutter build apk --release   # produces an installable APK
flutter install               # installs it to the connected device
```

(If `android/key.properties` is absent, release builds fall back to the debug
signing key so this still works.)

## Notes

- The Dart package is still named `ev3_controller` internally (it's only used
  in `import` paths); the user-facing name is **BrickLogic** and the store ID
  is `dev.perpaterb.bricklogic`.
- Desktop (Linux) builds — used for development — are unrelated to this:
  `flutter run -d linux`.
