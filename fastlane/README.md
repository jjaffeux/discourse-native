fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

### beta

```sh
[bundle exec] fastlane beta
```

Build and upload iOS, macOS, and Android testing releases

----


## iOS

### ios preflight

```sh
[bundle exec] fastlane ios preflight
```

Run local checks and create an unsigned iOS archive

----


## Android

### android verify

```sh
[bundle exec] fastlane android verify
```

Verify Google Play credentials and access to the app's internal testing track

### android build

```sh
[bundle exec] fastlane android build
```

Build a signed Android App Bundle for Google Play internal testing

### android beta

```sh
[bundle exec] fastlane android beta
```

Build and upload an Android release to Google Play internal testing

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
