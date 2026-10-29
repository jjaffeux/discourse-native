import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// The current layout of a page's retracting heading.
enum DPageHeaderLayout { standard, expanded, compact }

/// A page's identity, live header retraction, and owning scroll action.
///
/// The value is zero while its heading is fully visible and one when retracted.
/// Unlike layout geometry, this listenable supports widget builders. Motion
/// updates during the animation frame; build/layout changes publish afterward.
class DPageHeader extends ChangeNotifier implements ValueListenable<double> {
  DPageHeader({required this.scrollToTop});

  /// Returns only this page to its physical top, respecting reduced motion.
  final Future<void> Function() scrollToTop;
  String? _titleText;
  DPageHeaderLayout _layout = DPageHeaderLayout.standard;
  double _value = 0;
  bool _scheduled = false;
  bool _disposed = false;

  String? get titleText => _titleText;
  DPageHeaderLayout get layout => _layout;
  @override
  double get value => _value;

  /// Supplies the current presentation from the owning Native page surface.
  void update({
    required String? titleText,
    required double retraction,
    required DPageHeaderLayout layout,
  }) {
    assert(retraction >= 0 && retraction <= 1);
    if (_titleText == titleText && _value == retraction && _layout == layout) {
      return;
    }
    _titleText = titleText;
    _value = retraction;
    _layout = layout;
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      notifyListeners();
    } else if (!_scheduled) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduled = false;
        if (!_disposed) notifyListeners();
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Makes a page's header contract available to its heading, controls and body.
class DPageHeaderScope extends StatefulWidget {
  const DPageHeaderScope({
    super.key,
    required this.header,
    required this.child,
    this.active = true,
  });

  final DPageHeader header;
  final Widget child;
  final bool active;

  static DPageHeader? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HeaderScope>()?.header;

  @override
  State<DPageHeaderScope> createState() => _DPageHeaderScopeState();
}

class _DPageHeaderScopeState extends State<DPageHeaderScope> {
  _DPageHeaderHostState? _host;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _register();
  }

  @override
  void didUpdateWidget(DPageHeaderScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _register();
  }

  void _register() {
    final host = context.dependOnInheritedWidgetOfExactType<_HostScope>()?.host;
    _host?.withdraw(this);
    _host = host;
    if (!widget.active || !TickerMode.valuesOf(context).enabled) return;
    var depth = 0;
    context.visitAncestorElements((_) {
      depth++;
      return true;
    });
    host?.register(this, widget.header, depth);
  }

  @override
  void dispose() {
    _host?.withdraw(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _HeaderScope(header: widget.header, child: widget.child);
}

class _HeaderScope extends InheritedWidget {
  const _HeaderScope({required this.header, required super.child});
  final DPageHeader header;
  @override
  bool updateShouldNotify(_HeaderScope oldWidget) => header != oldWidget.header;
}

/// Shares the innermost foreground page header with surrounding chrome.
///
/// Changing [identity] drops the previous route immediately. Retained pages
/// with disabled tickers and excluded sheet underlays cannot supply a title.
/// The builder's listenable changes only when the owning page changes; listen
/// to the selected [DPageHeader] for text and motion.
class DPageHeaderHost extends StatefulWidget {
  const DPageHeaderHost({
    super.key,
    required this.identity,
    required this.builder,
    required this.child,
  });

  final Object identity;
  final Widget child;
  final Widget Function(
    BuildContext context,
    ValueListenable<DPageHeader?> header,
    Widget child,
  )
  builder;

  static Widget exclude({required Widget child}) =>
      _HostScope(host: null, identity: null, child: child);

  @override
  State<DPageHeaderHost> createState() => _DPageHeaderHostState();
}

class _DPageHeaderHostState extends State<DPageHeaderHost> {
  final _active = ValueNotifier<DPageHeader?>(null);
  final _headers = <Object, ({DPageHeader header, int depth})>{};
  bool _scheduled = false;

  void register(Object owner, DPageHeader header, int depth) {
    _headers[owner] = (header: header, depth: depth);
    _publish();
  }

  void withdraw(Object owner) {
    if (_headers.remove(owner) != null) _publish();
  }

  void _publish() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      DPageHeader? header;
      var depth = -1;
      for (final entry in _headers.values) {
        if (entry.depth >= depth) {
          header = entry.header;
          depth = entry.depth;
        }
      }
      _active.value = header;
    });
  }

  @override
  void didUpdateWidget(DPageHeaderHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity) {
      _headers.clear();
      _active.value = null;
    }
  }

  @override
  void dispose() {
    _active.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _HostScope(
    host: this,
    identity: widget.identity,
    child: widget.builder(context, _active, widget.child),
  );
}

class _HostScope extends InheritedWidget {
  const _HostScope({
    required this.host,
    required this.identity,
    required super.child,
  });
  final _DPageHeaderHostState? host;
  final Object? identity;
  @override
  bool updateShouldNotify(_HostScope oldWidget) =>
      host != oldWidget.host || identity != oldWidget.identity;
}
