# Assigned group query ownership

`AssignedGroupController` retains one private account owner per site. Its captured
plugin lease owns both query histories: up to 16 member searches and 16 topic
filters. Reading or loading a query updates its recency; completing a request
never changes cache order. Same-account navigation therefore retains bounded
query history without carrying private assignment results into another account.

Public getters only read the current account. Explicit member or topic loading
admits a successor after retirement; pagination cannot create one. Each query
uses its account's captured lease and its own request identity for credentials,
HTTP publication and cleanup. An earlier account's success, failure or finally
callback cannot change the successor query or publish a spurious notification.

Retirement removes the exact account before clearing its queries and notifying
presentation. Owned topic records are cleared before notification can admit a
successor. A borrowed topic store stays intact: retiring private feed IDs does
not erase records shared with other features. If an earlier retirement observer
already admitted a successor, the previous account's delayed observer cannot
clear its records or caches. Disposal closes admission before releasing accounts.

`AssignedGroupPresentationController` reads the domain getters and forwards its
change notifications to the retained view. Bare account retirement therefore
empties existing private rows immediately, without requiring a route replacement
or a separate plugin `forget` callback. Reload then uses new credentials.

A retirement observer on every cached query would duplicate account cleanup and
retain up to 32 observers per site. One account owner groups the shared lifetime
while keeping member and topic request policies distinct. This does not change
public SDK APIs, endpoint knowledge or the existing per-query cache limits.

The controller, view and link suites pin bounded recency, pagination, retained
presentation, default reload, borrowed records, credentials, late responses and
successor admission from an earlier retirement observer.
