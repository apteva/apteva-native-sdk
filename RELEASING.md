# Releasing the native SDK

Release Apple and Android from the same tested Git commit. Keep
`contract/contract-version.json`, `AptevaClientContract.version`, Android's
contract version, and `gradle.properties` aligned. Existing release tags and
assets must never be replaced to fix a release; publish a new patch version.

1. Run `swift test` on macOS and compile the UIKit product with an iOS SDK.
2. Run `./gradlew :android:testDebugUnitTest :android:assembleRelease` with
   Java 17 and Android API 37 installed.
3. Use `:android:publishReleasePublicationToMavenLocal` to inspect the exact
   versioned AAR, sources JAR, POM and Gradle metadata. Package the version's
   Maven directory under `ai/apteva/native-sdk/<version>/` in
   `apteva-native-sdk-<version>-maven.zip`.
4. Commit all release source, push `main`, and create an annotated
   `v<version>` tag on that exact commit.
5. Run `node scripts/package-release.mjs` after the local publication and tag
   are ready. Create a GitHub release with the Maven ZIP and individual Android artifacts,
   `SHA256SUMS`, and `release-manifest.json`. The manifest records the Git SHA,
   contract version and artifact checksums. Record the tested toolchains and
   test results in the release notes.
6. Check an independent Swift Package Manager resolution and an Android Maven
   consumer. Pin consuming apps to the exact released version.

The Git repository is the Swift package distribution channel. GitHub release
assets distribute the Android Maven-layout archive; a separate Maven host is
optional. No signing keys, app credentials, local Gradle properties, generated
build caches or application source belong in this SDK repository.
