# TestFlight releases

One Fastlane lane builds and uploads the iOS and macOS apps from
`profiles/full`, a compatibility wrapper around the same always-bundled
manifest used by the root app. It queries
App Store Connect first, then assigns two unused integer build numbers so the
two platform builds never share the same bundle ID, version, and build tuple.

## One-time setup

1. Add both iOS and macOS to the same App Store Connect app record. Both builds
   use the `org.discourse.native` bundle ID.
2. In Xcode, sign in to an account with access to developer team `6T3LU73T8S`.
   Xcode uses that account to create or download the distribution certificates
   and provisioning profiles needed by automatic signing.
3. Create an App Store Connect API key with App Manager access. Store the `.p8`
   key and the Fastlane JSON file outside this repository. The JSON format is:

   ```json
   {
     "key_id": "ABC123DEFG",
     "issuer_id": "00000000-0000-0000-0000-000000000000",
     "key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
   }
   ```

4. Copy `fastlane/.env.example` to `fastlane/.env`, set the absolute JSON path,
   and replace the export-compliance placeholder with `true` or `false`. Do not
   guess the encryption answer: confirm the classification for the app's HTTPS
   and RSA authentication use first.

## Release

Start from a clean worktree and pass the user-visible version:

```sh
bundle exec fastlane beta version:1.0.1
```

The lane performs these steps:

1. Resolves the root app, native CallKit bridge, and compatibility wrapper,
   then runs formatting, analysis, and the complete application tests.
2. Fetches the latest iOS and macOS build numbers from App Store Connect.
3. Configures Flutter and builds signed `.ipa` and `.pkg` artifacts.
4. Uploads both artifacts to TestFlight.

Artifacts and archives are retained under `build/testflight/`. By default the
lane waits for both builds to finish processing so it can apply the configured
export-compliance answer. To return after Apple accepts both uploads and let App
Store Connect continue processing asynchronously, run:

```sh
bundle exec fastlane beta version:1.0.1 wait_for_processing:false
```

The asynchronous form can leave the builds in `Missing Compliance` until that
answer is supplied in App Store Connect.

For an exceptional local run, `skip_checks:true` bypasses checks and
`allow_dirty:true` bypasses the clean-worktree guard. Neither should be used for
a normal release.
