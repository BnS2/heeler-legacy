<div align="center">

<img src="docs/images/logo.png" width="96" alt="Heeler logo" />

# Heeler Legacy

**[Heeler](https://github.com/ZingerLittleBee/Heeler) for iPhones and iPads stuck on iOS 16 and 17.**

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-6F42C1?style=flat-square)](LICENSE)
[![iOS](https://img.shields.io/badge/iOS-16%2B-000000?logo=apple&logoColor=white&style=flat-square)](https://developer.apple.com/ios/)

</div>

---

Heeler is a native iOS client for [herdr](https://herdr.dev): it connects to your
own machines over SSH and lets you watch and steer the coding agents running
there. The official app needs iOS 18. This fork lowers that to iOS 16.0 so it
runs on older hardware, such as the 5th-generation iPad, which stops at
iPadOS 16.7.

This is an unofficial fork. It is not on the App Store and is not supported by
the Heeler or herdr maintainers. If your device runs iOS 18, use the
[official app](https://apps.apple.com/us/app/heeler-for-herdr/id6797263135).

## Install

Source is available now. A downloadable IPA is pending final build verification.

Download `Heeler-ios16.ipa` from the
[latest release](https://github.com/BnS2/heeler-legacy/releases) and install it
with [Sideloadly](https://sideloadly.io) or AltStore using your Apple ID.
The IPA is unsigned; your sideloading tool signs it.

With a free Apple ID the install lasts 7 days, then you reinstall the same IPA.
See [the sideload guide](docs/guides/ios16-sideload.md) for limits and for
building the IPA yourself.

Setting up herdr and adding a machine work the same as upstream: follow the
[Heeler README](https://github.com/ZingerLittleBee/Heeler#installation) and its
[docs](https://docs.heeler.bybee.dev).

## What's different from upstream

**To run on iOS 16**

- Deployment target 16.0. The widgets extension stays on iOS 18 and is left out
  of the iOS 16 build.
- `@Observable` stores moved to `ObservableObject`, with explicit change
  forwarding where SwiftUI no longer tracks reads on its own.
- Stand-ins for `Synchronization.Mutex`, SwiftUI's `Spring`, the iOS 18 `Tab`
  API and other newer SwiftUI modifiers.
- `onChange` wrapper that passes the new value, so code no longer reads a stale
  `scenePhase` on iOS 16.
- Live Activities need iOS 16.2 and are off below it.
- Keychain falls back to the app's own group when the app-group entitlement is
  missing, as it is under free-account signing.

**Changes for older iPads**

- Voice input uses Apple speech recognition by default, with no API key.
  Recognition runs locally when supported; otherwise audio goes to Apple.
  You can turn this off in Settings.
- Chat is the default Agent view; typing into the raw terminal on an iPad
  keyboard is clumsy.
- Tapping anywhere in a terminal brings up the keyboard.
- A terminal attach stuck on "Connecting" for 15 seconds is retried once.
- Reconnect backoff tops out at 8 seconds instead of 30, and returning to the
  app retries a reconnecting Host right away.
- RSA keys are imported once instead of on every signature.

## Not working or untested

- No widgets, push notifications or app groups with a free Apple ID.
- Tailscale, ZeroTier and EasyTier are untested on iOS 16. Their prebuilt
  libraries target iOS 18.
- Earlier builds were tried on a 5th-generation iPad (iPadOS 16.7). The release
  build has not been verified on a physical device. Reports are welcome.

## Building

Same toolchain as upstream (Xcode, `make help`). Two differences:

- The overlay network binaries are not in the repository. See
  [Packages/HeelerOverlayNatives](Packages/HeelerOverlayNatives/README.md).
- Unit tests build for iOS 18 and run on a current simulator.

[docs/guides/ios16-sideload.md](docs/guides/ios16-sideload.md) has the
IPA build steps.

## License

Apache 2.0, same as upstream. Heeler is by
[ZingerLittleBee](https://github.com/ZingerLittleBee) and contributors; this
fork's changes are listed above and in the commit history.
