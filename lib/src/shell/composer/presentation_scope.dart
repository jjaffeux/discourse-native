import 'package:flutter/widgets.dart';

import '../../models/composer_placement.dart';
import '../desktop_panels_layout.dart';
import '../platform.dart';

/// Where the forum's selected draft stands on screen. Other open drafts wait
/// behind it in the composer's tabs, each keeping its own state.
enum ComposerActivity { none, writing, minimized }

/// What the shell around a composer asks about how it is presented.
///
/// The host that mounts the composer compiles every composer widget, while the
/// sidebar, title bar, and reader only need these facts.
abstract interface class ComposerPresentationView {
  DesktopPanelsLayout? get panelsLayout;
  Key get contentKey;
  Key get dockKey;
  Listenable get layoutChanges;
  void minimizeComposer();
  void restoreComposer();
  void redockForNavigation();
}

class ComposerPresentationScope extends InheritedWidget {
  const ComposerPresentationScope({
    super.key,
    required this.view,
    required this.hasMobileSheet,
    required super.child,
  });

  final ComposerPresentationView view;

  // Keep this presentation snapshot stable throughout a back event, even if
  // another PopScope callback synchronously starts saving and hides the draft.
  final bool hasMobileSheet;

  /// Borrows the window layout for passive composer control artwork.
  static DesktopPanelsLayout? panelsLayoutOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ComposerPresentationScope>()
      ?.view
      .panelsLayout;

  // The key is stable for the host's lifetime; reading it must not subscribe
  // the shell layout to composer presentation updates.
  static Key contentKeyOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<ComposerPresentationScope>()!
      .view
      .contentKey;

  static Key dockKeyOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ComposerPresentationScope>()!
      .view
      .dockKey;

  static Listenable layoutChangesOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ComposerPresentationScope>()!
      .view
      .layoutChanges;

  /// Reports whether the presented sheet owns mobile back navigation.
  static bool hasMobileSheetOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ComposerPresentationScope>()!
      .hasMobileSheet;

  static void minimizeComposer(BuildContext context) => context
      .getInheritedWidgetOfExactType<ComposerPresentationScope>()
      ?.view
      .minimizeComposer();

  static void restoreComposer(BuildContext context) => context
      .getInheritedWidgetOfExactType<ComposerPresentationScope>()
      ?.view
      .restoreComposer();

  /// Reveals sidebar destinations while retaining the current draft and dock.
  static void redockForNavigation(BuildContext context) {
    if (context.isTouch) return;
    context
        .getInheritedWidgetOfExactType<ComposerPresentationScope>()
        ?.view
        .redockForNavigation();
  }

  @override
  bool updateShouldNotify(ComposerPresentationScope oldWidget) => true;
}

/// Publishes [ComposerActivity] apart from [ComposerPresentationScope], which
/// notifies on every host rebuild, so a control following only this answer
/// sits out dock resizes.
class ComposerActivityScope extends InheritedWidget {
  const ComposerActivityScope({
    super.key,
    required this.activity,
    required super.child,
  });

  final ComposerActivity activity;

  static ComposerActivity of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ComposerActivityScope>()
          ?.activity ??
      ComposerActivity.none;

  @override
  bool updateShouldNotify(ComposerActivityScope oldWidget) =>
      activity != oldWidget.activity;
}

/// The edge of the app workspace whose border is owned by the resize handle.
class ComposerWorkspacePlacementScope extends InheritedWidget {
  const ComposerWorkspacePlacementScope({
    super.key,
    required this.placement,
    required super.child,
  });

  final ComposerPlacement? placement;

  /// Null when there is no expanded app-level composer.
  static ComposerPlacement? placementOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ComposerWorkspacePlacementScope>()
      ?.placement;

  @override
  bool updateShouldNotify(ComposerWorkspacePlacementScope oldWidget) =>
      placement != oldWidget.placement;
}

/// The room a parked draft takes over a phone's bar, its gap included, so the
/// bar's footer keeps pages clear of it.
class ComposerParkedDraftScope extends InheritedWidget {
  const ComposerParkedDraftScope({
    super.key,
    required this.room,
    required super.child,
  });

  final double room;

  /// 0 while no parked draft is shown.
  static double roomOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ComposerParkedDraftScope>()
          ?.room ??
      0;

  @override
  bool updateShouldNotify(ComposerParkedDraftScope oldWidget) =>
      room != oldWidget.room;
}
