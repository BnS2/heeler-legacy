# Building and sideloading the iOS 16 IPA

Devices on iOS 16 are often too old for `devicectl` (`make install-ipad` cannot
see them), so the app goes on as an unsigned IPA that Sideloadly or AltStore
signs with your Apple ID.

## Build the IPA

1. Put the overlay network frameworks in place
   ([Packages/HeelerOverlayNatives](../../Packages/HeelerOverlayNatives/README.md)).
2. Build Release without signing:

   ```bash
   xcodebuild -project Heeler.xcodeproj -scheme Heeler -configuration Release \
     -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/dd -jobs 1 \
     CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
   ```

3. Copy `build/dd/Build/Products/Release-iphoneos/Heeler.app` into an empty
   `Payload/` folder.
4. Delete `Payload/Heeler.app/PlugIns`. The widgets extension needs iOS 18, and
   with a free Apple ID every extension uses up another App ID.
5. Delete every `_CodeSignature` folder under `Payload/Heeler.app/Frameworks/`.
   Leftover ad-hoc signatures on CEasyTier, CTailscale and CZeroTier make the
   install fail with `ApplicationVerificationFailed ... CEasyTier.framework`
   (0xe8008001).
6. COpenSSL and CLibSSH2 are stamped with a minimum OS of 18.0, which dyld on
   iOS 16 refuses to load. Restamp each binary `B` (`vtool` cannot edit a fat
   file with one slice, so thin it first):

   ```bash
   lipo -thin arm64 B -output B.1
   vtool -set-build-version 2 16.0 18.0 -replace -output B B.1
   rm B.1
   ```

7. `zip -qry Heeler-ios16.ipa Payload`, then open the IPA in Sideloadly.

## Free Apple ID limits

- The install expires after 7 days. Reinstall the same IPA to renew it.
- At most 3 sideloaded apps at once, and about 10 new App IDs per 7 days.
  Rebuilding with the same bundle id does not use a new one.
- No push notifications, app groups, Live Activities or widgets. The keychain
  fallback in `Sources/Heeler/Transport/SecretStore.swift` exists because the
  app-group entitlement is missing under this signing.
