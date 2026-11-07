# HTTP client identity

`http_transport.dart` owns `discourseUserAgent`, the identity sent by native API,
appearance, media, and live-update requests. It retains the established wire
value `DiscourseNative/1.0`, which lets Discourse recognize anonymous native
requests under its crawler policy.

HTTP producers read this constant directly from the transport policy layer.
They do not import the endpoint facade to obtain client identity. The former
facade/transport aliases and separate appearance-loader literal are removed.
`SiteTracker` imports API exception contracts directly for its lookup failures.

A separate identity service would add lifecycle and injection machinery for a
fixed wire constant. Keeping aliases on endpoint classes would retain the
inverted media-to-endpoint dependency. One low-level declaration supplies the
existing request paths without changing header override, authentication,
redirect, cancellation, timeout, or response policy.

Existing transport contract, byte cache, tracker, and appearance loader tests
exercise the producers after this ownership change.
