#!/bin/zsh
set -eu
root=$1/bin/cache
shift
engine=$root/artifacts/engine
benchmark=$1
out=$2
mkdir -p "$out/Runner.app/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets" "$out/Runner.app/Contents/MacOS"
contents=$out/Runner.app/Contents
framework=$contents/Frameworks/App.framework
appfw=$framework/Versions/A
ln -sfn A "$framework/Versions/Current"
ln -sfn Versions/Current/App "$framework/App"
ln -sfn Versions/Current/Resources "$framework/Resources"
enginefw=$engine/darwin-x64-release/FlutterMacOS.xcframework/macos-arm64_x86_64
"$root/dart-sdk/bin/dartaotruntime" "$engine/darwin-x64/frontend_server_aot.dart.snapshot" \
  --sdk-root="$engine/common/flutter_patched_sdk_product/" --target=flutter --target-os=macos \
  --aot --tfa --no-embed-source-text -Ddart.vm.product=true \
  --packages="$3" --output-dill="$out/app.dill" "$benchmark"
"$engine/darwin-x64-release/gen_snapshot_arm64" --snapshot_kind=app-aot-macho-dylib \
  --macho="$appfw/App" --macho-min-os-version=11.0 --macho-install-name=@rpath/App.framework/App "$out/app.dill"
ln -sfn "$enginefw/FlutterMacOS.framework" "$contents/Frameworks/FlutterMacOS.framework"
cat >"$out/main.m" <<'OBJC'
#import <Cocoa/Cocoa.h>
#import <FlutterMacOS/FlutterMacOS.h>

int main() {
  @autoreleasepool {
    FlutterEngine* engine = [[FlutterEngine alloc] initWithName:@"benchmark"
      project:nil allowHeadlessExecution:YES];
    if (![engine runWithEntrypoint:nil]) return 1;
    [[NSRunLoop currentRunLoop] run];
    [engine shutDownEngine];
    return 2;
  }
}
OBJC
clang -fobjc-arc -fmodules -fmodules-cache-path="$out/clang-cache" -F"$enginefw" -framework FlutterMacOS \
  -framework Cocoa -Wl,-rpath,@executable_path/../Frameworks -o "$contents/MacOS/Runner" "$out/main.m"
cat >"$contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Runner</string>
<key>CFBundleIdentifier</key><string>org.discourse.benchmark</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
cat >"$appfw/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>App</string>
<key>CFBundleIdentifier</key><string>io.flutter.flutter.app</string>
<key>CFBundlePackageType</key><string>FMWK</string>
</dict></plist>
PLIST
