# Network recovery

A request that fails once must not leave the reader holding an error they have
to tap out of. Three pieces handle that, each with one owner.

## Reachability

`data/origin_reachability.dart` holds, per origin, whether the site can be
connected to. `DiscourseRequestCoordinator` reports every admitted request to
it:

- a failure that provably never opened a connection (`connectionNeverOpened`:
  a failed host lookup, a refused connection, an unreachable network) marks the
  origin unreachable;
- any response, whatever its status, marks it reachable;
- a timeout, a reset, a failed handshake or a broken kept-alive connection
  decides nothing, because each can follow a request the site received.

Outcomes are ordered by dispatch, so a slow failure cannot overrule a response
to a request sent after it. While an origin is unreachable the transport sends
it `HEAD /srv/status` on a jittered backoff from two seconds to a minute; the
probe carries no credentials and goes through the origin gate like any other
request. After thirty unanswered probes an origin is left alone until the app
returns to the foreground or one of its own requests fails again.

No platform connectivity plugin feeds this. An interface coming up says little
about whether one forum answers, and the request outcomes already say exactly
that. `OriginReachability.probeNow()` is where such a hint would go; the app
calls it when it returns to the foreground.

## One retry for a GET that never connected

A shared GET whose connection never opened is admitted a second time after
400 to 900 ms. It waits in the gate again, so backlog bounds and a rate-limit
cooldown still apply, and callers arriving meanwhile join it. A first failure
that the retry recovers from is not reported as an outage. Writes, uploads and
every ambiguous failure are sent once: a user API key gets no idempotency from
Discourse.

## Reloading what failed

`shell/network_recovery.dart` decides when: the current site's origin answering
after being unreachable, and the app returning to the foreground. The shell
says what: feeds whose load or page ended in an error, a category list in an
error state, and each tab's open topic whose read failed. Content that loaded
without error is not asked for again, and nothing is re-driven while the origin
is in a rate-limit cooldown; what was skipped for one waits for the next
foreground or recovery, not for the cooldown's end. Each reload is the ordinary load, so the existing request tokens
still drop a result that a newer load has superseded.

`network_status_banner.dart` shows the notice while the current site is
unreachable. It listens to the reachability notifier, not to the shell.

## Waiting on a site from elsewhere

Work held back while a site is away, such as a queue of deferred sends, can
subscribe with `ShellController.networkRecovery.onSiteRecovered`, or below the
shell with `OriginReachability.onRecovered`. The listener receives the origin
once per unreachable-to-reachable transition.
