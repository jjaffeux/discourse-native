# Profile write transactions

`ProfileWriteTransactions` owns presence and status write admission, credential acquisition, transport, settlement and transient account state. `ShellController` composes it and forwards its existing profile controls. The owner imports no shell controller or shell scope.

## Caller usage

```dart
final writes = ProfileWriteTransactions(
  currentUser: currentUser,
  api: siteApi,
  credentials: credentials,
  lifecycle: lifecycle,
  userStatuses: userStatuses,
  doNotDisturb: doNotDisturb,
  changed: changed,
);
await writes.setStatus(siteUrl, description: 'Working', emoji: 'house');
await writes.togglePresence(siteUrl);
writes.forget(siteUrl);
writes.dispose();
```

`ProfileCurrentUser` supplies a profile snapshot, the existing current-user reconciler, forced refresh, field confirmation and persistence. The shell adapter reads and updates canonical instance records. The owner stores no second user record. `CurrentUserDirectory` and `CurrentUserReconciler` retain freshness and field precedence. `UserStatusOverrides` retains live status authority, and `DoNotDisturbController` retains pause, resume and expiry policy. Store records and public UI workflows are unchanged.

## Account lifetime

Each private account record captures its original lease and reconciler, independent of the selected account. Presence and status attempts carry that record. Ownership requires the same live record and, for an attempt, the same pending identity. Lease retirement removes only its original record. Explicit forget releases the original presence precedence hold even when the lease remains current. Disposal is idempotent and rejects further admission.

Credential reads validate both original lease and attempt ownership before and after private storage IO. Reentrant listeners can forget, retire or dispose an owner without allowing its next credential read or dispatch. A late completion cannot publish into a successor or clear its busy state.

## Publication contract

On an active account, presence starts with an optimistic projection while the canonical value remains confirmed. Start and settlement advance the captured reconciler's presence revision. Success confirms only presence and persists before the shell notification. Failure restores the confirmed projection, retains the existing error and does not persist. Forced presence refreshes retain their existing overlapping request and error behavior.

Status sends the submitted description and emoji, then normalizes the confirmed local status after acceptance. It records the override, confirms the canonical own-user status, notifies and persists before optional DND work. Each observable effect is followed by an ownership check. A listener that retires the account stops subsequent effects. An accepted status remains accepted when later DND work fails. The status remains busy through DND settlement.

Expiry is validated after credential IO and again before notification pause. Existing error messages, missing-key outcomes and DND expiry rules remain unchanged. An uncertain write is never retried automatically.

## Design and verification

A single semantic current-user capability was chosen over extracting another canonical account repository. The latter would move adjacent ownership without reducing transaction policy. Model the Domain groups original lease, reconciler and pending state in one record. Laziness Protocol keeps the canonical stores and private status intent/result types.

`profile_write_transactions_test.dart` constructs the production owner without a Flutter binding. It pins normal publication cadence, normalization, retirement during credential IO and observable effects, same-URL successors, original reconciler cleanup and idempotent disposal. The presence, status ownership, DND expiry, current-user, shell ordering and Native profile suites cover the production adapter and persisted results. Reproduced lifetime corrections are committed separately from the standalone extraction. No performance improvement is claimed.
