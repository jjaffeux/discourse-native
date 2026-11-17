import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Hears a [Listenable] for something that can be kept out of sight with its
/// tickers off, as a page held offstage for a swipe is. While tickers are off
/// here it holds what it hears and says it once when they run again, so a
/// hidden subtree does no work for changes nobody sees and is current in the
/// frame that shows it.
final class DShownListening {
  DShownListening(this._onChanged);

  final VoidCallback _onChanged;
  Listenable? _source;
  ValueListenable<TickerModeData>? _mode;
  bool _held = false;

  /// Follows [source] from [context]. Call from `didChangeDependencies`, and
  /// again whenever the source may have been replaced.
  void attach(BuildContext context, Listenable source) {
    final mode = TickerMode.getValuesNotifier(context);
    if (!identical(mode, _mode)) {
      _mode?.removeListener(_modeChanged);
      _mode = mode..addListener(_modeChanged);
    }
    if (!identical(source, _source)) {
      _source?.removeListener(_heard);
      _source = source..addListener(_heard);
    }
  }

  void _heard() {
    if (_mode?.value.enabled ?? true) {
      _onChanged();
    } else {
      _held = true;
    }
  }

  void _modeChanged() {
    if (!_held || !_mode!.value.enabled) return;
    _held = false;
    _onChanged();
  }

  void dispose() {
    _mode?.removeListener(_modeChanged);
    _source?.removeListener(_heard);
    _mode = null;
    _source = null;
  }
}

/// A [ListenableBuilder] that builds again only while it can be seen: see
/// [DShownListening].
class DShownListenableBuilder extends StatefulWidget {
  const DShownListenableBuilder({
    super.key,
    required this.listenable,
    required this.builder,
    this.child,
  });

  final Listenable listenable;
  final TransitionBuilder builder;
  final Widget? child;

  @override
  State<DShownListenableBuilder> createState() =>
      _DShownListenableBuilderState();
}

class _DShownListenableBuilderState extends State<DShownListenableBuilder> {
  late final _listening = DShownListening(() => setState(() {}));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listening.attach(context, widget.listenable);
  }

  @override
  void didUpdateWidget(DShownListenableBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _listening.attach(context, widget.listenable);
  }

  @override
  void dispose() {
    _listening.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.child);
}
