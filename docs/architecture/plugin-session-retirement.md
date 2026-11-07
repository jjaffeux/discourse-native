# Plugin session retirement

`PluginSession.close` owns one teardown operation. It publishes the operation's
completion before revoking consumer authority or entering lifecycle code. A
revocation or lifecycle callback that reenters `close` joins that same operation;
it cannot revoke consumers again or create a second teardown queue entry.

Every later caller observes that completion, including after teardown has started
or failed. The closing and closed flags control admission of new hooks; they are
not evidence that asynchronous cleanup has finished. A second caller must not
release shared transport or other resources while a contribution still owns
pending cleanup. The completion retains the original aggregate failure.

Consumer authority is revoked synchronously. Operations already in the lifecycle
queue drain before teardown. Contributions close in reverse order, and revocation
and lifecycle failures accumulate without preventing remaining contributions
from closing. A local completion bridges the existing queue's result; no second
lifecycle state machine or cleanup history is introduced.

`plugin_runtime_test.dart` holds teardown behind a gate and verifies repeated and
synchronously reentrant callers remain pending until it settles, observe the same
failure, and revoke consumers once. Combined revocation and contribution failures
remain visible in the aggregate. Existing runtime tests retain hook ordering and
session-before-plugin-before-transport cleanup coverage.
