# Flag transactions

`FlagTransactions` owns post and topic flag validation, admission, credential reads, dispatch, publication and cleanup. The shell supplies the public facade and a synchronous `FlagSiteContext` snapshot of connection state, the current action catalog and message limits. It does not expose itself to the owner.

Each account session retains its original `SiteLease`. Retirement removes only that session and clears its topic attempts. Completion releases only its original attempt. A replacement account at the same URL can begin a topic flag while the old request finishes. Forget and disposal retire the same state without publishing late results.

`TopicDataSession.beginPostWrite` remains the sole admission authority for post flags and competing canonical post writes. The flag owner does not add another post lock. Accepted post responses pass through `acceptPostAction`, including bookmark preservation. Accepted topic flags update the currently held `TopicDetail` rather than the captured opening record.

Validation uses the currently held record and current catalog reason matched by ID. Required explanations use the original untrimmed message and configured limits. Other reasons send no message. Flags retain their nullable localized error results. Retired successful continuations return the connection-changed error; late transport refusals retain the existing server or unreachable message. A lost response never triggers another write.

The standalone owner was chosen over a private shell part because concrete dependencies prevent accidental access to shell state. Store and TopicDataSession retain canonical data. The account session contains only flag lifetime and topic admission metadata.

`flag_transactions_test.dart` drives the real owners without initializing a Flutter binding. It covers duplicate admission, credential retirement, reentrant publication, same-URL replacement, original-operation cleanup, competing post holds and disposal. The existing controller and Native editor suites preserve validation strings, authoritative responses, opening target ownership and visuals.
