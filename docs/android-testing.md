# Deploy an Android build to internal testing

Build the complete application from `profiles/full`. Its Android application ID
is `org.discourse.native`, matching the existing Google Play app and Apple ID.
The Android code namespace is `org.discourse.nativeapp` because `native` is a
Java keyword. The code namespace and application ID are separate Gradle settings.

## Install the build tools

Install Flutter from `.fvmrc`, the [native image build tools](../README.md#native-image-build-tools), and the Ruby dependencies:

```sh
bundle install
brew install openjdk@17 android-commandlinetools
flutter config --android-sdk /opt/homebrew/share/android-commandlinetools \
  --jdk-dir /opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
```

Install the SDK packages. Review and accept the Android SDK license when prompted:

```sh
JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
  sdkmanager 'platforms;android-36' 'build-tools;36.0.0' 'platform-tools' \
  'ndk;28.2.13676358' 'cmake;3.22.1'
```

## Configure upload signing

Create an upload keystore outside the repository using
[Flutter's Android signing instructions](https://docs.flutter.dev/deployment/android#sign-the-app).
Keep a secure backup of the keystore and its passwords. Reuse this key for
subsequent uploads.

Create an external `key.properties` file with these entries:

```properties
storeFile=/absolute/path/to/upload.jks
storePassword=YOUR_STORE_PASSWORD
keyAlias=upload
keyPassword=YOUR_KEY_PASSWORD
```

Restrict the keystore and properties file to your user. Set
`ANDROID_KEY_PROPERTIES` in your shell or the ignored `fastlane/.env` file:

```sh
export ANDROID_KEY_PROPERTIES=/absolute/path/to/key.properties
```

Release builds require this configuration and never use the debug signing key.

## Configure push notifications

Native uses the existing `discourse-mobile-app` Firebase project and Mothership's
`/api/publish_android` publisher.

1. Open [Firebase project settings](https://console.firebase.google.com/project/discourse-mobile-app/settings/general).
2. Under **Your apps**, add an Android app with package name `org.discourse.native`.
   If that package is already registered, select the existing app.
3. Download its `google-services.json` file to
   `profiles/full/android/app/google-services.json`.
4. In **Project settings > Cloud Messaging**, confirm that **Firebase Cloud
   Messaging API (V1)** is enabled. Keep Mothership's existing service account and
   `gcm-notifications-key` secret. App signing and Play publishing credentials are
   separate from FCM credentials.
5. Include the same configuration file on machines that build Android releases.
   The file contains public app configuration and can be committed. Keep
   service-account private keys outside the app.

Follow [Firebase's Android setup instructions](https://firebase.google.com/docs/android/setup)
if you need to download the configuration again. The package name must match
the application ID, including case. The Kotlin namespace `org.discourse.nativeapp`
is not the Firebase package name.

Install the build on a device with Google Play services. Connect or reconnect a
site and allow notifications when Android asks. Reconnection associates the FCM
token with the site's user API key. As on Apple platforms, token changes require
new authorization; ordinary requests do not migrate a key to a new push token.

Trigger a mention or private-message notification from another account. Check
delivery with the app in the foreground, in the background, and closed. Tap each
notification and check that it opens the correct site and post. A force-stopped
app must be opened again before FCM can deliver messages.

For a Firebase Console test message, add a `discourse_url` custom data field with
an absolute HTTPS site URL. Mothership supplies this URL inside its JSON `payload`
data field. Native accepts both forms.

The Google services Gradle plugin processes the configuration file. No FlutterFire
CLI setup or Apple Firebase configuration is needed for this Android integration.

## Upload the first build

From the repository root, build a signed Android App Bundle:

```sh
bundle exec fastlane android build version:1.0.0 build_number:1
```

The bundle is saved as `build/google-play/Discourse-1.0.0-1.aab`.
For an intentional build of uncommitted changes, add `allow_dirty:true`.

In [the Discourse Play Console app](https://play.google.com/console/u/2/developers/8730084763525300360/app/4973858912327675063/app-dashboard):

1. Open **Test and release > Testing > Internal testing**.
2. Create a release and upload the bundle.
3. Complete any Play App Signing agreement presented by Google.
4. Add release notes, review the release, and roll it out to internal testing.
5. Select your testers and share the opt-in link with them.

This Play Console app requires the package ID `org.discourse.native`. Fastlane
[requires an initial manual upload](https://docs.fastlane.tools/actions/upload_to_play_store/#quick-start)
before using the publishing API.

## Automate subsequent uploads

The dedicated service account is
`discourse-native-fastlane@discourse-mobile-app.iam.gserviceaccount.com` in the
`discourse-mobile-app` project. Its Play Console access is limited to
`org.discourse.native`, with read access and **Release apps to testing tracks**.
The publishing API is enabled in that project.

Follow [Google's API setup guide](https://developers.google.com/android-publisher/getting_started)
if you need to recreate the account. In Play Console, grant it access to this app
with **View app information** and **Release apps to testing tracks**. Keep
production release and account administration permissions disabled.

Store the service-account JSON outside the repository. Configure its path:

```sh
export GOOGLE_PLAY_JSON_KEY_PATH=/absolute/path/to/google-play-service-account.json
```

Verify the credentials and this app's internal track before uploading:

```sh
bundle exec fastlane android verify
```

The command prints the existing internal version codes and does not upload a release.

The usual beta command builds and uploads iOS, macOS, and Android together:

```sh
bundle exec fastlane beta version:1.1.0 skip_checks:true
```

The command selects build numbers from TestFlight and Google Play. It builds
all three apps before uploading any of them. Android releases go directly to
the internal testing track. Both stores' credentials and Android signing must
be configured before the command starts building.

To upload Android alone:

```sh
bundle exec fastlane android beta version:1.1.0
```

Android selects the next version code from the app's uploaded bundles and APKs,
independently of the marketing version. You can pass `build_number:` to the
Android-only lane to select a code explicitly. Add `draft:true` to save an Android
release as a draft instead of making it available to testers.
The upload lane targets internal testing and skips store metadata, images, and screenshots.

## Verify Android changes

From `profiles/full/android`, run the native push tests:

```sh
./gradlew :app:testDebugUnitTest --tests 'org.discourse.nativeapp.*'
```

Run the storage and draft tests by file path. On an Android emulator or test
device, run the native smoke test from `profiles/full`:

```sh
flutter test integration_test/android_smoke_test.dart -d emulator-5554
```

The Android host stores credentials with Android Keystore-backed AES-GCM and
disables app backup. Drafts use the application-support private file store.
Native call integration needs separate platform work.
