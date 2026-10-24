# Consuming the native client SDK

Place `apteva-native-sdk` beside each app repository for local development.
The SDK owns transport, authentication, realtime, wire models, and native
surface contracts; apps own navigation, platform UI, signing, and release flows.

## Apple

For released Apple apps, reference the exact Git package version in XcodeGen:

```yaml
packages:
  AptevaNativeSDK:
    url: https://github.com/apteva/apteva-native-sdk.git
    exactVersion: 1.4.0
```

iOS/iPadOS targets depend on products `AptevaNativeSDK` and
`AptevaNativeUIKit`; macOS depends on `AptevaNativeSDK`. Import the product
module in consuming Swift files. Regenerate the Xcode project and retain the
resolved package state. Do not compile SDK sources directly into app targets.
For SDK development only, use `path: ../apteva-native-sdk` instead.

## Android

The app declares `implementation("ai.apteva:native-sdk:1.4.0")`. Its
`settings.gradle.kts` substitutes the sibling SDK checkout for that coordinate
when present. Without the sibling checkout, configure a Maven repository URL
with `aptevaSdkMavenUrl` or `APTEVA_SDK_MAVEN_URL`. For a private repository,
also provide `aptevaSdkMavenUser` / `aptevaSdkMavenToken` (or the matching
environment variables). Do not commit credentials. GitHub releases include
`apteva-native-sdk-<version>-maven.zip`, a local Maven repository containing the
versioned AAR, POM and Gradle metadata. Verify it against the release's
`SHA256SUMS`, extract it, and set `APTEVA_SDK_MAVEN_URL` to that directory's
absolute `file://` URL. This avoids requiring a separate Maven host.

The SDK's `release` publication produces an Android AAR at the same coordinate.
After choosing a Git host/Maven repository, provide `aptevaSdkPublishUrl`,
`aptevaSdkPublishUser`, and `aptevaSdkPublishToken` (or matching
`APTEVA_SDK_PUBLISH_*` environment variables) to opt in to remote publication.
No publication happens as part of local builds.

Keep the Apple tag, Android artifact version, and `contract/contract-version.json`
aligned when making a contract release. Native apps cannot import this package
from npm; Swift Package Manager and Maven are the native distribution channels.
