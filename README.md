# discourse-native

wip

## TestFlight build setup

Install the Ruby dependencies and the Xcode build log formatter before running
Fastlane:

```sh
bundle install
brew install xcbeautify
```

Both iOS and macOS TestFlight builds use `xcbeautify`, the
[formatter recommended by Fastlane](https://docs.fastlane.tools/best-practices/xcodebuild-formatters/).
