import 'dart:async';
import 'dart:math';

import '../foundation/frame_safe_notifier.dart';
import 'connection_never_opened.dart';

/// Whether each origin can currently be connected to, as its own requests
/// report it.
///
/// A failure that provably never opened a connection marks its origin
/// unreachable; any response, whatever its status, marks it reachable again.
/// Timeouts, resets and TLS failures decide nothing: each can happen on a
/// working network.
///
/// Outcomes are ordered by when their request was dispatched, not by when it
/// settled, so a lookup that fails slowly cannot overrule a response from a
/// request sent after it.
///
/// Listeners hear every change of any origin's state. [onRecovered] is the
/// narrower signal for work that waits on a site: it fires once per
/// unreachable-to-reachable transition, after the state has changed.
final class OriginReachability extends FrameSafeNotifier {
  OriginReachability({
    Random? random,
    this.firstProbeDelay = const Duration(seconds: 2),
    this.maximumProbeDelay = const Duration(seconds: 60),
    this.maximumProbes = 30,
  }) : assert(firstProbeDelay > Duration.zero),
       assert(maximumProbes > 0),
       assert(maximumProbeDelay >= firstProbeDelay),
       _random = random ?? Random();

  final Random _random;
  final Duration firstProbeDelay;
  final Duration maximumProbeDelay;

  /// An origin that stays silent this long is one nobody may be waiting for:
  /// a mistyped address, a lapsed domain, a site since removed. It is left
  /// alone until [probeNow] or another of its own requests failing.
  final int maximumProbes;

  /// Requests report their outcomes from inside their own zones, which carry
  /// an account scope and a scheduling intent. Timers, probes and recovery
  /// listeners must not inherit those from whichever request happened to
  /// report, so each runs in a zone captured away from any request.
  final Zone _zone = Zone.current;

  final Map<String, _Unreachable> _unreachable = {};
  final Map<String, int> _decidedBy = {};
  final List<void Function(String)> _recovered = [];
  int _dispatches = 0;

  /// Sends one cheap request to [origin] through the owner's ordinary request
  /// path, so that its outcome is reported back here like any other. Without
  /// one, an unreachable origin recovers only when other work succeeds.
  Future<void> Function(Uri origin)? probe;

  bool isReachable(String origin) => !_unreachable.containsKey(origin);

  bool isUrlReachable(Uri url) => isReachable(url.origin);

  /// Marks a request's dispatch. Its outcome is reported with the returned
  /// token.
  int dispatched() => ++_dispatches;

  void succeeded(Uri url, int dispatch) {
    if (isDisposed || !_decides(url.origin, dispatch)) return;
    final held = _unreachable.remove(url.origin);
    if (held == null) return;
    held.timer?.cancel();
    notifySafely();
    for (final listener in _recovered.toList()) {
      if (_recovered.contains(listener)) listener(url.origin);
    }
  }

  void failed(Uri url, Object error, int dispatch) {
    if (isDisposed || !connectionNeverOpened(error)) return;
    final origin = url.origin;
    if (!_decides(origin, dispatch)) return;
    final held = _unreachable[origin];
    if (held != null) {
      if (held.timer == null) _schedule(held);
      return;
    }
    _schedule(_unreachable[origin] = _Unreachable(Uri.parse(origin)));
    notifySafely();
  }

  bool _decides(String origin, int dispatch) {
    if (dispatch <= (_decidedBy[origin] ?? 0)) return false;
    _decidedBy[origin] = dispatch;
    return true;
  }

  /// Calls [listener] after an unreachable origin answers again. The returned
  /// callback removes it.
  ///
  /// The listener runs in the zone that registered it, and an error it throws
  /// is reported there: recovery is announced from inside the request that
  /// proved it, and that request's result is not the listener's to fail.
  void Function() onRecovered(void Function(String origin) listener) {
    final bound = Zone.current.bindUnaryCallbackGuarded(listener);
    _recovered.add(bound);
    return () => _recovered.remove(bound);
  }

  /// A hint that the network may have changed: the app returned to the
  /// foreground, or the platform reported a new route. Unreachable origins are
  /// probed now rather than when their backoff next allows.
  void probeNow() {
    if (isDisposed) return;
    for (final held in _unreachable.values.toList()) {
      held.attempts = 0;
      _probe(held);
    }
  }

  void _schedule(_Unreachable held) {
    held.timer?.cancel();
    held.timer = null;
    if (probe == null || held.attempts >= maximumProbes) return;
    final exponent = held.attempts.clamp(0, 16);
    final ceiling = firstProbeDelay * (1 << exponent);
    final base = ceiling > maximumProbeDelay ? maximumProbeDelay : ceiling;
    // Sites that went away together would otherwise all be asked together.
    final delay = base * (0.75 + _random.nextDouble() * 0.5);
    held.timer = _zone.createTimer(delay, () => _probe(held));
  }

  void _probe(_Unreachable held) {
    held.timer?.cancel();
    held.timer = null;
    final send = probe;
    if (send == null || held.probing) return;
    held.attempts++;
    held.probing = true;
    unawaited(
      _zone
          .run(() => Future<void>.sync(() => send(held.origin)))
          .then<void>((_) {}, onError: (Object _, StackTrace _) {})
          .whenComplete(() {
            held.probing = false;
            // A probe that proved nothing either way reported nothing, and
            // would otherwise be the last one.
            if (!isDisposed &&
                identical(_unreachable[held.origin.origin], held) &&
                held.timer == null) {
              _schedule(held);
            }
          }),
    );
  }

  @override
  void dispose() {
    for (final held in _unreachable.values) {
      held.timer?.cancel();
    }
    _unreachable.clear();
    _recovered.clear();
    super.dispose();
  }
}

final class _Unreachable {
  _Unreachable(this.origin);

  final Uri origin;
  Timer? timer;
  int attempts = 0;
  bool probing = false;
}

/// What recovery needs to know about a site's connection: whether its origin
/// answers, and whether it has asked to be left alone.
abstract interface class SiteReachabilityApi {
  OriginReachability get reachability;

  bool isCoolingDown(String siteUrl);
}
