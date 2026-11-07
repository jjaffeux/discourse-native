# Account retirement errors

`SiteLifecycle` removes the account generation before running its retirement
observers. Retiring captures and clears the original observer list, then runs
all its callbacks synchronously, even if one fails. After cleanup it rethrows
the first error with its original stack trace. Later callback failures do not
replace that failure.

This preserves the existing throwing contract while making callback failure
independent from other owners' cleanup. Requests, media caches, timers, and
plugin observations do not rely on an earlier observer returning successfully.
A callback may create a successor at the same URL; old retirement still owns
only the captured generation. Registering on an already retired lease remains
an immediate callback, including immediate error propagation.

`AccountSessionCoordinator` clears host-owned account state in a `finally`
around lifecycle invalidation. An observer failure therefore cannot skip the
host cleanup. The error still follows the existing connection/disconnection
failure path; this change does not turn retirement into a nonthrowing operation
or add automatic retries, reporting hooks, or another dispatcher.

Reporting each failure asynchronously would change caller error policy.
Stopping at the first error retains that policy but leaves unrelated resources
active. Complete synchronous fanout followed by the original first error keeps
both cleanup ownership and caller-visible failure explicit.

`site_lifecycle_test.dart` covers a middle observer failure, multiple failures,
original stack preservation, idempotent invalidation, and a reentrant successor.
`account_session_coordinator_test.dart` verifies host cleanup and issued-key
compensation after a retirement observer fails. The four new cases failed
against the previous implementation. Existing request-session and media owner
tests exercise actual cancellation and resource cleanup on retirement.
