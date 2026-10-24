# Preview loading

`PreviewLoadingOwner` owns user-card and post-liker request lifetimes. The shell resolves the selected or explicit site, then calls `loadUserCard(instance, username, force)` or `loadLikers(instance, postId)`. The owner acquires key-only credentials, dispatches through the existing API capabilities, publishes to canonical Store, and completes its request state. It has no ShellController reference or callbacks into shell policy.

`UserCard` and `PostLikers` remain only in Store. `UserStatusOverrides` remains the live status authority used by existing presentation selectors. The public shell facades and two independent `PreviewRequests` notifiers remain available. Progress and failures never notify the shell facade.

User cards coalesce by lowercase username and send the original username to HTTP. Ordinary loads skip a cached card or error; `force` permits retry. Likers coalesce only while pending and refetch on each later load. Both retain anonymous access and read no client ID. Existing lookup and unexpected-error messages remain unchanged.

## Account and request ownership

Each site has a private account identity captured before begin-notification, with one detachable retirement observer and separate typed request maps. Each accepted request has a private identity. The owner checks both identities before credential IO, before transport, before Store publication, and before completion. Store publication can notify a listener synchronously, so completion checks ownership again.

Retirement removes the original account and clears both original notifier states before either notifies. A cleanup listener can immediately start a successor at the same URL without old cleanup removing it. An earlier retirement observer can also start successor work before the preview owner's observer runs. Account lookup retires the stale owner and reuses any successor created during cleanup. Old success, failure and finally paths cannot publish or finish successor requests.

Completed requests release their request identities. The account observer remains until retirement so existing errors clear with their account. Retirement and disposal detach that observer. Shell site cleanup no longer supplies preview request cleanup.

`preview_loading.dart` is a private Dart part of `preview_requests.dart`. This keeps account/request identities and the coordinated notifier reset private without adding a public silent-clear operation.

## Alternatives and verification

One concrete domain owner was compared with two typed loader instances. The typed loaders would need callbacks for casing, cache and force policy, HTTP dispatch, publication, and error mapping, or duplicate lifetime machinery. The concrete owner keeps these two small domain policies explicit behind two loading operations. Model the Domain guided the account/request identities; Laziness Protocol avoided a general loader framework.

The existing preview, account-lifecycle, popover, status and rebuild suites passed before and after extraction. `preview_loading_test.dart` drives the production owner and canonical Store without a Flutter binding. Controlled credential and response completions cover retirement, response order, reentrant notification, error mapping, retry, site isolation and disposal. A separate fix commit addresses the reproduced pending-state leak after lifecycle retirement.
