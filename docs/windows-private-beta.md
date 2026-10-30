# Build the Windows private beta

Use the **Windows MSIX** GitHub Actions workflow to produce an x64 package for
Discourse Native's existing Microsoft Store private audience.

1. Open **Actions → Windows MSIX → Run workflow** on the branch you want to build.
2. Enter an unused Store version such as `1.0.1.0`. Increase the first three
   components for each Store upload. The final component must remain `0`.
3. Wait for the storage tests, native startup test, and release build to pass.
4. Download the `DiscourseNative-<version>-x64` workflow artifact and extract it.
5. Upload the `.msix` file under **Packages** in Discourse Native's Partner Center
   submission. Keep **Pricing and availability → Private audience** selected.
6. Complete the Store listing, privacy policy, and age rating, then submit the
   private submission for certification.

The package uses the identity registered for Store product `9PP3N4BHGZ3K`.
Microsoft signs it during Store processing. No signing certificate, PFX password,
or developer certificate installation is required for this build.
The workflow does not upload to or publish the Store.

## Build on a Windows development machine

Install Flutter `3.47.7`, Visual Studio 2022 with **Desktop development with C++**,
the Windows SDK, Rust `1.92.0`, Meson `1.9.1`, Ninja `1.13.0`, and NASM `2.16.03`.
Run these commands from a Visual Studio x64 Developer PowerShell terminal.

```powershell
$env:RUSTUP_TOOLCHAIN = '1.92.0'
flutter doctor -v
./tool/build_windows_msix.ps1 -StoreVersion 1.0.1.0
```

The package appears at
`build/windows/msix/DiscourseNative-1.0.1.0-x64.msix`.
The script verifies the package identity, architecture, version, executable,
Flutter engine, and required Visual C++ runtime DLLs. The `msix` package selects
the runtime DLLs from the installed Visual Studio redistributable.

An unsigned Store package cannot be installed directly as a sideloaded package.
Use `flutter run -d windows` for local development. Testers install the certified
private build from the Store while signed in with an account in the tester group.

## Check the Windows client

Install the [Microsoft Edge WebView2 Evergreen Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)
if it is absent. Authentication and embedded media require it. Windows 11 includes
the runtime, but Windows 10 installations may need it separately.

Run the native startup and credential persistence check on Windows.

```powershell
flutter test integration_test/windows_smoke_test.dart -d windows
```

Before inviting more testers, sign in to a test forum, restart the app, post and
restore a draft, upload a file, play embedded media, and check Voice microphone
and screen sharing permissions. The automated smoke check exercises the runner,
DPAPI encryption, durable credential reads, deletion, and the first Flutter frame.
It does not authenticate against a live forum or exercise real media devices.

Windows credentials use user-scoped DPAPI encryption in an atomically replaced
application-support document. Drafts use the existing application-support store.
Document locks coordinate concurrent Windows isolates and app processes.
