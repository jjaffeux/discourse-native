/// The longest a write waits in place before handing its refusal to the user.
/// Longer than this and the action looks stuck rather than briefly delayed.
const Duration maximumInlineRetryWait = Duration(seconds: 60);

/// How long a sender holds after a refusal that named [retryAfter]. A limit
/// nothing timed still must not be hit again at once.
Duration retryWaitAfter(Duration? retryAfter) {
  final wait = retryAfter ?? const Duration(seconds: 1);
  return wait.isNegative ? Duration.zero : wait;
}

/// The whole seconds to show for [wait], rounded up so a wait still running
/// never reads as none.
int waitSeconds(Duration wait) =>
    (wait.inMicroseconds / Duration.microsecondsPerSecond).ceil();
