# discourse-native

wip

See [Composer ownership](docs/composer-architecture.md) for the live editor,
built-in component modules, and plugin extension points.

## TestFlight build setup

Install the Ruby dependencies and the Xcode build log formatter before running
Fastlane:

```sh
bundle install
brew install xcbeautify
```

Both iOS and macOS TestFlight builds use `xcbeautify`, the
[formatter recommended by Fastlane](https://docs.fastlane.tools/best-practices/xcodebuild-formatters/).
