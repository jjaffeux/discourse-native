import 'package:flutter/widgets.dart';

import '../data/site_lifecycle.dart';
import '../foundation/foreground_lifecycle.dart';
import 'reader_media_activity.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';

/// Collects reader inputs without making the activity owner depend on a binding.
mixin ReaderMediaHost<T extends StatefulWidget> on State<T> {
  final mediaActivity = ReaderMediaActivity();
  late final _mediaHost = _ReaderMediaHostBinding(this);

  bool get mediaNeedsGeometry => false;
  GlobalKey? get mediaSourceAnchor => null;

  void mediaAccountRetired();

  SiteLease? mediaAccountFor(String? siteUrl, {SiteLifecycle? lifecycle}) =>
      siteUrl == null
      ? null
      : (lifecycle ?? _mediaHost._shell?.lifecycle)?.capture(siteUrl);

  @override
  void initState() {
    super.initState();
    _mediaHost.initialize();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mediaHost.update();
  }

  void scheduleMediaGeometry() => _mediaHost.scheduleGeometry();

  @override
  void dispose() {
    _mediaHost.dispose();
    mediaActivity.dispose();
    super.dispose();
  }
}

final class _ReaderMediaHostBinding with WidgetsBindingObserver {
  _ReaderMediaHostBinding(this.host);

  final ReaderMediaHost host;
  ShellController? _shell;
  ScrollableState? _scrollable;
  ScrollPosition? _position;
  bool _foreground = true;
  bool _geometryVisible = false;
  bool _geometryScheduled = false;

  void initialize() {
    _foreground = isForegroundLifecycle(WidgetsBinding.instance.lifecycleState);
    WidgetsBinding.instance.addObserver(this);
    host.mediaActivity.present(
      foreground: _foreground,
      rowVisible: true,
      geometryVisible: !host.mediaNeedsGeometry,
    );
  }

  void update() {
    final shell = ShellScope.maybeIdentityOf(host.context);
    final replacedShell = !identical(shell, _shell);
    if (!identical(shell, _shell)) {
      _shell?.removeListener(_accountChanged);
      _shell = shell;
      shell?.addListener(_accountChanged);
    }
    final scrollable = host.mediaNeedsGeometry
        ? Scrollable.maybeOf(host.context)
        : null;
    final position = scrollable?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(scheduleGeometry);
      _position = position;
      position?.addListener(scheduleGeometry);
    }
    _scrollable = scrollable;
    _present(replaceAccount: replacedShell);
    if (host.mediaNeedsGeometry) scheduleGeometry();
  }

  void _accountChanged() {
    final attachment = host.mediaActivity.attachment;
    if (attachment != null && !attachment.isCurrent) {
      _present();
    }
  }

  void _present({bool replaceAccount = false}) {
    final attachment = host.mediaActivity.attachment;
    final retired =
        attachment != null && (replaceAccount || !attachment.isCurrent);
    if (retired) host.mediaActivity.retire();
    host.mediaActivity.present(
      foreground: _foreground,
      rowVisible: host.mounted
          ? TickerMode.valuesOf(host.context).enabled
          : true,
      geometryVisible: !host.mediaNeedsGeometry || _geometryVisible,
    );
    if (retired) host.mediaAccountRetired();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = isForegroundLifecycle(state);
    _present();
  }

  void scheduleGeometry() {
    if (_geometryScheduled || !host.mediaNeedsGeometry) return;
    _geometryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _geometryScheduled = false;
      if (!host.mounted) return;
      final source = host.mediaSourceAnchor?.currentContext?.findRenderObject();
      var visible = false;
      if (source is RenderBox && source.attached && source.hasSize) {
        final view = View.of(host.context);
        var viewport =
            Offset.zero & (view.physicalSize / view.devicePixelRatio);
        final scrollViewport = _scrollable?.context.findRenderObject();
        if (scrollViewport is RenderBox &&
            scrollViewport.attached &&
            scrollViewport.hasSize) {
          viewport = viewport.intersect(
            scrollViewport.localToGlobal(Offset.zero) & scrollViewport.size,
          );
        }
        final origin = source.localToGlobal(Offset.zero);
        visible =
            origin.dx.isFinite &&
            origin.dy.isFinite &&
            !viewport.isEmpty &&
            (origin & source.size).overlaps(viewport);
      }
      _geometryVisible = visible;
      _present();
    });
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shell?.removeListener(_accountChanged);
    _position?.removeListener(scheduleGeometry);
  }
}
