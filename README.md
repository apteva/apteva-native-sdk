# Apteva Native SDK

This directory is the reusable client boundary for native Apteva applications.
It is intentionally independent of app-specific UI, navigation, release
targets, and bundle identifiers so it can move to its own repository and be
versioned as a dependency of independently maintained apps.

## Layout

- `contract/`: canonical client behavior and endpoint contract shared by every
  platform implementation.
- `apple/`: Swift sources built by `Package.swift` as `AptevaNativeSDK` and
  `AptevaNativeUIKit` (authenticated image support for iOS/iPadOS).
- `android/`: standalone Android library module producing a Maven AAR.

## Ownership boundary

The SDK owns:

- server URL validation and API path construction;
- cookie and bearer authentication transport;
- password-login to private device-key exchange;
- typed server models and endpoint methods;
- authenticated REST, SSE, native-surface, media, and push API contracts;
- canonical HTTP/error classification;
- secure credential primitives;
- realtime connection and chat reconciliation primitives.

Each app owns:

- screens, navigation, design, accessibility, and platform interaction;
- bundle/application identifiers and signing;
- notification presentation and destination routing;
- app lifecycle and project selection presentation;
- the product-specific decision of when to connect, restore, or disconnect.

Apps must not add ad-hoc `/api` calls outside this SDK. When the server contract
changes, update `contract/`, then the two platform SDK implementations. App
repositories should only need to update their SDK dependency version.

## Build and versioning

```sh
swift test
ANDROID_HOME="$HOME/Library/Android/sdk" ./gradlew :android:assembleRelease :android:testDebugUnitTest
```

The current SDK/contract version is `1.5.2`. The canonical Git repository is
https://github.com/apteva/apteva-native-sdk. Apple apps consume its exact
`1.5.2` Swift Package Manager version (Git tag `v1.5.2`). Android consumes
`ai.apteva:native-sdk:1.5.2`; release assets include the AAR, sources, POM,
Gradle module metadata, and a ZIP of the Maven repository layout. Download and
verify that ZIP to use a local Maven repository without a separate Maven host.
Sibling checkouts remain available for SDK development. See `RELEASING.md` for
the release checks and artifact provenance requirements.

This is a native Swift/Kotlin SDK; npm would not make it consumable by Xcode or
Gradle. See [INTEGRATION.md](INTEGRATION.md) for dependency details.
