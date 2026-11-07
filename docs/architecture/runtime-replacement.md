# Runtime replacement and retirement failure

`AppRuntime.replace` records presentation-flag changes without recreating services.
A service change records its requested configuration and acquires replacement
ownership before retiring the existing controller. Reentrant replacement calls
return false without adopting or queuing their requested target, whether matching
or different. Incoming services are adopted only after retirement completes. Successful replacement retains unchanged services and constructs
its next controller with the latest flags. Notification ingress becomes available
again when that controller starts.

If controller retirement throws, the runtime restores its previous configuration
record and enters its existing disposed state. It retires notification ingress and schedules only its current services for
cleanup before rethrowing the original error with its stack. It neither installs
an incoming plugin manifest nor adopts or closes distinct incoming dependencies.
Further startup, lifecycle, replacement and disposal calls cannot reactivate it.
The controller getter retains the old disposed controller, as after ordinary
runtime disposal; there is no partially active replacement.

The same private service-cleanup operation serves disposal and failed replacement.
Controller plugin-session teardown finishes first. An installation owned by the
runtime closes next, then its API transport closes. Injected plugin installations
remain externally owned. The transport stays available while session and owned
plugin teardown perform their final requests. Repeated disposal cannot queue a
second transport closure.

A disposed controller cannot be rolled back into service. Constructing a successor
before retiring the previous controller would overlap shared service sessions;
continuing after failed retirement would assume that cleanup was safe. Terminal
cleanup preserves the existing failure contract without claiming either recovery.

`app_runtime_test.dart` verifies a controlled retirement-observer failure, original
error and stack preservation, notification-stream cancellation, gated session and
plugin teardown order, exact-once API closure, untouched incoming dependencies,
external plugin ownership, matching replacement requests during retirement, and
no startup or lifecycle work after failure.

A disposal request made by a retirement observer marks the runtime disposed and
retires ingress immediately. The active replacement retains cleanup ownership;
it finishes the original controller's disposal and closes its captured services
once, without constructing an incoming controller. A retirement exception still
rethrows its original failure. Replacement ownership is released in a finally
block on successful, aborted and failed transitions.
