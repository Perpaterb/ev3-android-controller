# BrickLogic

Build your own controller for a LEGO Mindstorms EV3 — no code, just blocks.

BrickLogic is an Android app for kids (~10+) that connects to an EV3 brick over
Bluetooth. You design a controller (buttons, sliders, d-pads…) and wire up what
it does with UE5-Blueprint-style visual scripting, then hit Run and drive your
robot.

See [USER_STORIES.md](USER_STORIES.md) for the full feature plan.

## Development

Flutter app targeting **Android** (the real thing) and **Linux desktop** (for
development on Ubuntu).

```sh
flutter run -d linux      # desktop dev window
flutter build apk         # Android build
flutter test              # test suite
```
