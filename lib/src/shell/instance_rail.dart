import 'package:flutter/material.dart';

import '../diagnostics/diagnostics_scope.dart';
import '../models/discourse_instance.dart';
import '../models/site_appearance.dart';
import '../theme/app_theme.dart';
import '../theme/color_contrast.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'adaptive_activity_indicator.dart';
import 'add_instance_sheet.dart';
import 'avatar_image.dart';
import 'instance_actions.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'update_controller.dart';
import 'update_sheet.dart';

/// The far-left column of Discourse instances. Visible at every window size,
/// including on phones.
class InstanceRail extends StatelessWidget {
  const InstanceRail({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ShellSelector<_RailSnapshot>(
      select: _RailSnapshot.from,
      builder: (context, state, _) {
        final controller = ShellScope.read(context);
        return ListenableBuilder(
          listenable: controller.accountActivity.totalsListenable,
          builder: (context, _) => ColoredBox(
            color: theme.shell.rail,
            child: SafeArea(
              right: false,
              child: Column(
                children: [
                  Expanded(
                    child: switch (state.loadStatus) {
                      InstanceLoadStatus.loading => Center(
                        child: SizedBox.square(
                          dimension: 24,
                          child: AdaptiveActivityIndicator(
                            color: theme.shell.railForeground,
                            cupertinoRadius: 12,
                            materialStrokeWidth: 2,
                          ),
                        ),
                      ),
                      InstanceLoadStatus.failed => const _RailLoadFailure(),
                      InstanceLoadStatus.ready => ListView.builder(
                        // The traffic lights are cleared by the title bar above
                        // the shell, so the rail only needs this padding.
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        itemCount: state.instances.length,
                        itemBuilder: (context, index) {
                          final instance = state.instances[index];
                          return _RailItem(
                            key: ValueKey(instance.url),
                            instance: instance,
                            appearance: state.appearances[index],
                            selected: index == state.selectedIndex,
                            badgeCount: controller.railBadgeFor(instance),
                            onTap: () => controller.selectInstance(index),
                          );
                        },
                      ),
                    },
                  ),
                  _RailFooter(
                    siteActionsAvailable:
                        state.loadStatus == InstanceLoadStatus.ready,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RailSnapshot {
  _RailSnapshot.from(ShellController controller)
    : instances = controller.instances,
      appearances = [
        for (final instance in controller.instances)
          controller.siteAppearanceFor(instance.url),
      ],
      selectedIndex = controller.instanceIndex,
      loadStatus = controller.loadStatus;

  final List<DiscourseInstance> instances;
  final List<SiteAppearance?> appearances;
  final int selectedIndex;
  final InstanceLoadStatus loadStatus;

  @override
  bool operator ==(Object other) {
    if (other is! _RailSnapshot ||
        selectedIndex != other.selectedIndex ||
        loadStatus != other.loadStatus) {
      return false;
    }
    if (instances.length != other.instances.length) return false;
    for (var index = 0; index < instances.length; index++) {
      if (!identical(instances[index], other.instances[index])) return false;
      if (appearances[index] != other.appearances[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    selectedIndex,
    loadStatus,
    Object.hashAll(instances.map(identityHashCode)),
    Object.hashAll(appearances),
  );
}

class _RailLoadFailure extends StatelessWidget {
  const _RailLoadFailure();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Tooltip(
        message: 'Retry loading sites',
        child: InkWell(
          key: const ValueKey('instance-load-retry-rail'),
          onTap: ShellScope.read(context).load,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(22),
            ),
            child: DIcon(
              DIcons.arrowsRotate,
              size: 20,
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ),
    );
  }
}

/// App-level controls below the scrolling sites.
///
/// Diagnostics remains present while sites load or fail. Site mutation and
/// update controls wait until the persisted site snapshot is known.
class _RailFooter extends StatelessWidget {
  const _RailFooter({required this.siteActionsAvailable});

  final bool siteActionsAvailable;

  @override
  Widget build(BuildContext context) {
    final updates = ShellScope.read(context).updates;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (siteActionsAvailable) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Center(child: _AddInstanceButton()),
          ),
          // Whether this build can update at all is decided at compile time
          // and cannot change while running.
          if (updates.isSupported)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Center(child: _UpdateButton()),
            ),
        ],
        if (DiagnosticsScope.maybeRead(context) != null)
          const Padding(
            padding: EdgeInsets.fromLTRB(0, 4, 0, 8),
            child: Center(child: _DiagnosticsButton()),
          ),
      ],
    );
  }
}

/// The app-wide diagnostics entry. It subscribes only to panel visibility and
/// unseen errors, never to the event stream, so ordinary HTTP traffic cannot
/// rebuild the rail.
class _DiagnosticsButton extends StatelessWidget {
  const _DiagnosticsButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diagnostics = DiagnosticsScope.read(context);

    return ListenableBuilder(
      listenable: Listenable.merge([
        diagnostics.panelListenable,
        diagnostics.unseenErrorsListenable,
      ]),
      builder: (context, _) {
        final open = diagnostics.isPanelOpen;
        final unseen = diagnostics.unseenErrorCountListenable.value;
        final tooltip = unseen == 0
            ? 'Diagnostics'
            : 'Diagnostics, $unseen unseen ${unseen == 1 ? 'error' : 'errors'}';

        return Semantics(
          button: true,
          selected: open,
          label: tooltip,
          child: Tooltip(
            message: tooltip,
            child: InkWell(
              key: const ValueKey('diagnostics-rail-button'),
              onTap: diagnostics.togglePanel,
              borderRadius: BorderRadius.circular(22),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedContainer(
                    width: 44,
                    height: 44,
                    duration: const Duration(milliseconds: 180),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: open
                          ? theme.colorScheme.primary.withValues(alpha: 0.16)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(open ? 14 : 22),
                    ),
                    child: DIcon(
                      DIcons.bug,
                      size: 20,
                      color: open
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (unseen > 0)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      // The parent announces the exact unseen count. Keep the
                      // visually capped badge from adding a contradictory
                      // second number to the accessible label.
                      child: ExcludeSemantics(
                        child: _UnreadBadge(count: unseen),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The rail's update affordance.
///
/// Tapping always opens the sheet and never installs. Restarting the app out
/// from under someone is not something a single tap in a rail should be able to
/// do.
class _UpdateButton extends StatelessWidget {
  const _UpdateButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final updates = ShellScope.read(context).updates;

    // Subscribed here rather than through ShellScope, so that finding an update
    // re-badges this button without rebuilding the sidebar, the topic list and
    // everything else in the shell. Same reasoning as ComposerPanel.
    return ListenableBuilder(
      listenable: updates,
      builder: (context, _) {
        final version = updates.available?.version;

        final (tooltip, icon, color, filled) = switch (updates.status) {
          UpdateStatus.available => (
            'Update to $version',
            DIcons.download,
            theme.colorScheme.primary,
            true,
          ),
          UpdateStatus.readyToInstall => (
            'Restart to finish updating',
            DIcons.farCircleCheck,
            theme.colorScheme.primary,
            true,
          ),
          UpdateStatus.failed => (
            updates.error ?? 'The last update check failed',
            DIcons.triangleExclamation,
            theme.colorScheme.error,
            false,
          ),
          _ => (
            'Check for updates',
            DIcons.arrowsRotate,
            theme.shell.railForeground,
            false,
          ),
        };

        // An update waiting is not a problem, so the dot is the primary colour
        // rather than the error red _UnreadBadge uses. Same position and the
        // same 2px ring against the rail, so the two read as one family.
        final wants =
            updates.status == UpdateStatus.available ||
            updates.status == UpdateStatus.readyToInstall;

        return Tooltip(
          message: tooltip,
          child: InkWell(
            onTap: () => showUpdateSheet(context),
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: filled
                        ? color.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: updates.status == UpdateStatus.downloading
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            value: updates.progress,
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : DIcon(icon, size: 20, color: color),
                ),
                if (wants)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.shell.rail, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RailItem extends StatefulWidget {
  const _RailItem({
    super.key,
    required this.instance,
    required this.appearance,
    required this.selected,
    required this.badgeCount,
    required this.onTap,
  });

  final DiscourseInstance instance;
  final SiteAppearance? appearance;
  final bool selected;
  final int badgeCount;
  final VoidCallback onTap;

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _hovered = false;

  void _handleHover(bool hovered) {
    if (_hovered == hovered) return;
    setState(() => _hovered = hovered);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _activePalette(
      widget.appearance,
      MediaQuery.platformBrightnessOf(context),
    );
    final accent = palette?.tertiary ?? widget.instance.accentColor;
    final avatarBackground = widget.selected
        ? accent
        : accent.withValues(alpha: accent.a * 0.16);
    final scaffold = opaqueColorOnCanvas(
      theme.scaffoldBackgroundColor,
      theme.brightness,
    );
    final railSurface = Color.alphaBlend(theme.shell.rail, scaffold);
    final avatarForeground = contrastSafeForeground(
      background: avatarBackground,
      backdrop: railSurface,
      preferred: [
        if (!widget.selected) theme.shell.railForeground,
        palette?.secondary,
        palette?.primary,
        if (widget.selected) theme.shell.railForeground,
      ],
    );
    final indicatorHeight = widget.selected ? 40.0 : (_hovered ? 20.0 : 8.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // Discord-style marker: a dot at rest, half pill on hover and full
          // pill for the selected site, all growing out of the left edge.
          AnimatedContainer(
            key: ValueKey('instance-rail-marker-${widget.instance.url}'),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 4,
            height: indicatorHeight,
            decoration: BoxDecoration(
              color: theme.shell.railForeground,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(4),
              ),
            ),
          ),
          Center(
            child: InstanceActions(
              instance: widget.instance,
              child: _RailTooltip(
                instance: widget.instance,
                accent: accent,
                child: InkWell(
                  onTap: widget.onTap,
                  onHover: _handleHover,
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SizedBox.square(
                        dimension: 44,
                        child: _InstanceAvatar(
                          instance: widget.instance,
                          foreground: avatarForeground,
                          background: avatarBackground,
                          selected: widget.selected,
                        ),
                      ),
                      if (widget.badgeCount > 0)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: _UnreadBadge(count: widget.badgeCount),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The hover label for a forum in the rail.
///
/// The callout is small enough to scan while moving down the rail, but carries
/// the site's own mark so similarly named forums remain easy to distinguish.
/// Its transform grows from the pointer, keeping the label visually attached
/// to the icon throughout the entrance animation.
class _RailTooltip extends StatelessWidget {
  const _RailTooltip({
    required this.instance,
    required this.accent,
    required this.child,
  });

  static const hoverDelay = Duration(milliseconds: 280);
  static const dismissDelay = Duration(milliseconds: 80);
  static const animationStyle = AnimationStyle(
    duration: Duration(milliseconds: 120),
    reverseDuration: Duration(milliseconds: 80),
    curve: Curves.linear,
  );

  final DiscourseInstance instance;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);

    return RawTooltip(
      key: ValueKey(
        'instance-rail-tooltip-${instance.url}-${disableAnimations ? 'still' : 'motion'}',
      ),
      semanticsTooltip: instance.title,
      hoverDelay: hoverDelay,
      dismissDelay: dismissDelay,
      triggerMode: TooltipTriggerMode.manual,
      enableFeedback: false,
      animationStyle: disableAnimations
          ? AnimationStyle.noAnimation
          : animationStyle,
      positionDelegate: _positionRailTooltip,
      ignorePointer: true,
      tooltipBuilder: (context, animation) {
        final callout = ExcludeSemantics(
          child: RepaintBoundary(
            child: _RailTooltipCallout(instance: instance, accent: accent),
          ),
        );

        return _RailTooltipTransition(animation: animation, child: callout);
      },
      child: child,
    );
  }
}

class _RailTooltipTransition extends StatefulWidget {
  const _RailTooltipTransition({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  State<_RailTooltipTransition> createState() => _RailTooltipTransitionState();
}

class _RailTooltipTransitionState extends State<_RailTooltipTransition> {
  late CurvedAnimation _eased;

  @override
  void initState() {
    super.initState();
    _eased = _createAnimation();
  }

  @override
  void didUpdateWidget(_RailTooltipTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation == widget.animation) return;
    _eased.dispose();
    _eased = _createAnimation();
  }

  CurvedAnimation _createAnimation() => CurvedAnimation(
    parent: widget.animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void dispose() {
    _eased.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _eased,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(_eased),
        alignment: Alignment.centerLeft,
        child: widget.child,
      ),
    );
  }
}

class _RailTooltipCallout extends StatelessWidget {
  const _RailTooltipCallout({required this.instance, required this.accent});

  static const surface = Color(0xFF3C3D43);
  static const decoration = ShapeDecoration(
    color: surface,
    shape: _RailTooltipBorder(),
    shadows: [
      BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3)),
      BoxShadow(color: Color(0x24000000), blurRadius: 2, offset: Offset(0, 1)),
    ],
  );

  final DiscourseInstance instance;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconBackground = Color.alphaBlend(accent, surface);
    final iconForeground = contrastSafeForeground(
      background: iconBackground,
      backdrop: surface,
      preferred: const [Colors.white, Colors.black],
    );

    return Container(
      key: ValueKey('instance-rail-callout-${instance.url}'),
      constraints: const BoxConstraints(minHeight: 36, maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: decoration,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: AvatarImage(
                key: ValueKey('instance-rail-callout-icon-${instance.url}'),
                url: instance.iconUrl,
                size: 18,
                fit: BoxFit.contain,
                fallback: ColoredBox(
                  color: iconBackground,
                  child: SizedBox.square(
                    dimension: 18,
                    child: Center(
                      child: Text(
                        instance.monogram,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: iconForeground,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              instance.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: const Color(0xFFF3F3F4),
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.15,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Offset _positionRailTooltip(TooltipPositionContext context) {
  const horizontalGap = 6.0;
  const viewportMargin = 8.0;
  return Offset(
    _fitRailTooltip(
      wanted: context.target.dx + context.targetSize.width / 2 + horizontalGap,
      extent: context.overlaySize.width,
      childExtent: context.tooltipSize.width,
      margin: viewportMargin,
    ),
    _fitRailTooltip(
      wanted: context.target.dy - context.tooltipSize.height / 2,
      extent: context.overlaySize.height,
      childExtent: context.tooltipSize.height,
      margin: viewportMargin,
    ),
  );
}

double _fitRailTooltip({
  required double wanted,
  required double extent,
  required double childExtent,
  required double margin,
}) {
  if (!extent.isFinite || !childExtent.isFinite) return wanted;
  final slack = extent - childExtent;
  if (slack <= margin * 2) return slack / 2;
  return wanted.clamp(margin, slack - margin);
}

/// Rounded rail callout with a pointer aimed at the forum icon.
class _RailTooltipBorder extends OutlinedBorder {
  const _RailTooltipBorder({
    super.side = const BorderSide(color: Color(0xFF47484E)),
    this.pointerWidth = 7,
    this.pointerHeight = 14,
    this.radius = 7,
  });

  final double pointerWidth;
  final double pointerHeight;
  final double radius;

  @override
  EdgeInsetsGeometry get dimensions {
    final inset = side.strokeInset.clamp(0.0, double.infinity);
    return EdgeInsets.fromLTRB(pointerWidth + inset, inset, inset, inset);
  }

  Path _path(Rect rect) {
    if (rect.isEmpty) return Path();

    final body = Rect.fromLTRB(
      rect.left + pointerWidth,
      rect.top,
      rect.right,
      rect.bottom,
    );
    final corner = radius.clamp(0, body.shortestSide / 2);
    final pointerHalfHeight = pointerHeight.clamp(0, body.height) / 2;

    return Path()
      ..moveTo(body.left + corner, body.top)
      ..lineTo(body.right - corner, body.top)
      ..quadraticBezierTo(body.right, body.top, body.right, body.top + corner)
      ..lineTo(body.right, body.bottom - corner)
      ..quadraticBezierTo(
        body.right,
        body.bottom,
        body.right - corner,
        body.bottom,
      )
      ..lineTo(body.left + corner, body.bottom)
      ..quadraticBezierTo(
        body.left,
        body.bottom,
        body.left,
        body.bottom - corner,
      )
      ..lineTo(body.left, body.center.dy + pointerHalfHeight)
      ..lineTo(rect.left, body.center.dy)
      ..lineTo(body.left, body.center.dy - pointerHalfHeight)
      ..lineTo(body.left, body.top + corner)
      ..quadraticBezierTo(body.left, body.top, body.left + corner, body.top)
      ..close();
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return _path(rect.deflate(side.strokeInset));
  }

  @override
  _RailTooltipBorder copyWith({
    BorderSide? side,
    double? pointerWidth,
    double? pointerHeight,
    double? radius,
  }) {
    return _RailTooltipBorder(
      side: side ?? this.side,
      pointerWidth: pointerWidth ?? this.pointerWidth,
      pointerHeight: pointerHeight ?? this.pointerHeight,
      radius: radius ?? this.radius,
    );
  }

  @override
  ShapeBorder scale(double t) => _RailTooltipBorder(
    side: side.scale(t),
    pointerWidth: pointerWidth * t,
    pointerHeight: pointerHeight * t,
    radius: radius * t,
  );

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    final strokeOffset = (side.strokeOutset - side.strokeInset) / 2;
    canvas.drawPath(_path(rect.inflate(strokeOffset)), side.toPaint());
  }

  @override
  bool operator ==(Object other) {
    return other is _RailTooltipBorder &&
        other.side == side &&
        other.pointerWidth == pointerWidth &&
        other.pointerHeight == pointerHeight &&
        other.radius == radius;
  }

  @override
  int get hashCode => Object.hash(side, pointerWidth, pointerHeight, radius);
}

/// The site's own icon, falling back to a monogram while it loads or if the
/// site does not publish one.
class _InstanceAvatar extends StatelessWidget {
  const _InstanceAvatar({
    required this.instance,
    required this.foreground,
    required this.background,
    required this.selected,
  });

  final DiscourseInstance instance;
  final Color foreground;
  final Color background;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final monogram = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(selected ? 14 : 22),
      ),
      clipBehavior: Clip.antiAlias,
      child: Center(
        child: Text(
          instance.monogram,
          style: theme.textTheme.labelLarge?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AvatarImage(
        url: instance.iconUrl,
        size: 44,
        fit: BoxFit.contain,
        fallback: monogram,
      ),
    );
  }
}

ResolvedSitePalette? _activePalette(
  SiteAppearance? appearance,
  Brightness platformBrightness,
) {
  if (appearance == null) return null;
  return switch (appearance.mode) {
    SiteAppearanceMode.base => appearance.base ?? appearance.alternate,
    SiteAppearanceMode.alternate => appearance.alternate ?? appearance.base,
    SiteAppearanceMode.followSystem =>
      platformBrightness == Brightness.dark
          ? appearance.alternate ?? appearance.base
          : appearance.base ?? appearance.alternate,
  };
}

class _AddInstanceButton extends StatelessWidget {
  const _AddInstanceButton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: 'Add a Discourse site',
      child: InkWell(
        onTap: () => showAddInstanceSheet(context),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: theme.shell.railForeground.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(22),
          ),
          child: DIcon(
            DIcons.plus,
            size: 22,
            color: theme.shell.railForeground,
          ),
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      constraints: const BoxConstraints(minWidth: 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.error,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: theme.shell.rail, width: 2),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onError,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}
