# Welcome claim ownership

`PostWelcomeStore` owns welcome age eligibility and its viewer/post identity.
Its pure eligibility predicate runs at queued storage admission, so a claim that
waits beyond the calendar-month boundary is declined.
`OwnedSitePreferences<bool>.claim` owns the conditional stored transition from
absent or false to true. It shares the existing per-site preference operation
queue with writes, migrations and permanent removal. No second claim queue or
independent read/write/verification admission remains in the welcome store.

A claim captures the site's exact storage owner when called. It retains that
owner through reading and backend settlement. Retirement makes pending claims
return false; an admitted backend write finishes before queued deletion. A new
claim after retirement receives the successor owner and runs after deletion, so
old work cannot consume a successor's welcome or erase its stored claim.

An existing true value, storage rejection or exception returns false. Rejected
cache values retain the existing last-accepted-value policy, so a later attempt
can retry. Compatible legacy true values count as already claimed. Concurrent
claims through this application's shared preference owner grant one claim;
this is not a cross-process compare-and-swap guarantee.

Focused welcome tests reproduce retirement between the old separate read and
write admissions, gate backend settlement across retirement and re-add, and
verify rejection/exception retries and expiry while waiting for admission. Existing concurrent-store, identity, calendar
expiry, preference-retirement and confetti tests cover the surrounding contracts.
