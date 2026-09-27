import 'dart:ui' show AppLifecycleState;

/// Whether an app in [state] is still in front of the user.
///
/// `inactive` leaves the window on screen: it is the iOS app switcher or a
/// system dialog, and on macOS and Linux a visible window that merely lost
/// focus to another app. Only `hidden`, `paused` and `detached` leave the
/// foreground, and a binding that has not reported a state has not left it.
bool isForegroundLifecycle(AppLifecycleState? state) =>
    state != AppLifecycleState.hidden &&
    state != AppLifecycleState.paused &&
    state != AppLifecycleState.detached;
