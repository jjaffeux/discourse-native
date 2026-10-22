# Request scheduling intent

Ordinary API work is interactive. Optional metadata and speculation run inside
`RequestIntent.background().run(() => operation())`. The scope follows awaits,
including credential reads. Scope a finite request-producing operation; startup,
subscriptions and recurring timers must keep their normal caller context.

Transport captures the source once and forwards it through redirect hops. The
origin gate resolves current intent when a slot becomes free. Interactive work
can overtake at most three times while background work is eligible. Equal
priorities retain enqueue order. Independent origins have separate allowances;
a gate with an aggregate cap shares one allowance. Active requests keep their
slots. Cooldowns, backlog bounds and separate upload capacity still apply.

A speculative owner promotes its dedicated source when navigation adopts the
existing future. Safe GET sharing retains each caller's source and resolves the
highest intent. Joining a request never promotes its caller's other work. The
first sender runs in its initiating Zone; each waiter resumes in its own Zone.
Cancellable reads remain unshared, and credentials, headers and response limits
remain part of GET identity.

A cache that returns a held future bypasses transport admission. Such caches use
`RequestIntentOperation` and call `join()` for each subsequent consumer. This
covers presentation metadata and category hydration. Background classification
of another shared loader requires the same ownership before adding a scope.
Account/session refresh and bus topic/post refresh retain ordinary intent until
their separate duplicate-suppression owners support adoption.

The gate, coordinator, prefetch transport, presentation and startup test files
assert dispatch order, bounded overtakes, adoption during credentials, sibling
isolation, cooldowns and caller Zones. These tests verify policy, not a measured
latency improvement.
