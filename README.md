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
