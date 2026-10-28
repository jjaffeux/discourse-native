# discourse-native

wip

See [Composer ownership](docs/composer-architecture.md) for the live editor,
built-in component modules, and plugin extension points.

## Native image build tools

AVIF stills and animations use the source-built `flutter_libavif` decoder.
Install its build tools before running Flutter tests or building the app:

```sh
brew install cmake meson ninja nasm rustup
export PATH="$(brew --prefix rustup)/bin:$PATH"
rustup toolchain install 1.92.0 --profile minimal
export RUSTUP_TOOLCHAIN=1.92.0
```

On Linux, install `cmake meson ninja-build nasm` and [rustup](https://rustup.rs),
then select the same Rust toolchain. Apple cross-builds also need the target,
for example `rustup target add --toolchain 1.92.0 aarch64-apple-ios`.
CI installs these tools through `.github/actions/setup-avif`.

## TestFlight build setup

Install the Ruby dependencies and the Xcode build log formatter before running
Fastlane:

```sh
bundle install
brew install xcbeautify
```

Fastlane adds Homebrew's `rustup` to `PATH` and selects Rust `1.92.0`
automatically for every lane.

Both iOS and macOS TestFlight builds use `xcbeautify`, the
[formatter recommended by Fastlane](https://docs.fastlane.tools/best-practices/xcodebuild-formatters/).

## Google Play internal testing

See [Deploy an Android build to internal testing](docs/android-testing.md) for
Android SDK setup, upload signing, the first Play Console upload, and the
`fastlane android build` and `fastlane android beta` commands.

With both stores' credentials configured, the existing release command builds
all three platforms and publishes Android to internal testing:

```sh
bundle exec fastlane beta version:1.1.0 skip_checks:true
```

Apple build numbers come from TestFlight. Android selects the next version code
from the app bundles and APKs in Google Play, independently of the version name.
