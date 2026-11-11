part of 'main_content.dart';

class _MobilePageSheet extends StatelessWidget {
  const _MobilePageSheet({
    required this.route,
    required this.entry,
    required this.viewportKey,
    required this.reader,
    required this.underlay,
    this.readerKey,
  });

  final ContentRoute route;
  final Object entry;
  final Key viewportKey;
  final Key? readerKey;
  final Widget? reader;
  final Widget? underlay;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    return DSheetViewport(
      key: viewportKey,
      readerStart: reader == null || !route.isTopic
          ? null
          : shell.topicOpensAtTop(route.topicId!)
          ? DSheetReaderStart.top
          : DSheetReaderStart.scrolled,
      onDismiss: reader == null
          ? null
          : () {
              if (shell.mobileNavigation.entryId == entry) shell.handleBack();
            },
      underlay: underlay,
      content: reader == null
          ? null
          : DSheetContent(
              key: readerKey,
              side: DSheetSide.bottom,
              variant: DSheetVariant.page,
              showCloseButton: false,
              semanticLabel: route.title,
              backgroundColor: ForumWindowBackground.panelColor(context),
              children: [Expanded(child: reader!)],
            ),
    );
  }
}

class _MobileContentHost extends StatefulWidget {
  const _MobileContentHost({
    required this.owner,
    required this.state,
    required this.registry,
    required this.builder,
  });

  final Object owner;
  final _MainContentSnapshot state;
  final PluginRegistry registry;
  final Widget Function(_MainContentSnapshot, Key?, Widget?, Object?) builder;

  @override
  State<_MobileContentHost> createState() => _MobileContentHostState();
}

class _MobileContentHostState extends State<_MobileContentHost> {
  final _sourceBodyKey = GlobalKey();
  var _searchPageKey = GlobalKey();

  @override
  void didUpdateWidget(_MobileContentHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.owner != oldWidget.owner) _searchPageKey = GlobalKey();
  }

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    final tab = shell.tabContext(widget.state.activeTabId);
    final mobilePresentation = MobilePresentationScope.maybeOf(context);
    final presentation = ForumTabScope.panelOf(context) == null
        ? mobilePresentation
        : null;
    final stack = tab.contentStack;
    final searchIndex = stack.lastIndexWhere((route) => route.isGlobalSearch);
    final current = widget.state;
    final previousSheetEntry = shell.mobileNavigation.previousEntryId;
    final previousSheet = current.previousRoute;
    final currentRoute = current.route;
    final retainPreviousSheet =
        shell.mobileNavigationEnabled &&
        mobilePresentation != null &&
        previousSheetEntry != null &&
        currentRoute?.destination is ExtensionDestination &&
        previousSheet?.destination is ExtensionDestination &&
        mobilePresentation.usesSheet(currentRoute!) &&
        mobilePresentation.usesSheet(previousSheet!);
    final base = retainPreviousSheet
        ? _MainContentSnapshot.forRoute(
            shell,
            tab,
            previousSheet,
            previousRoute: mobilePresentation.previousOf(previousSheet),
          )
        : current;
    final baseEntry = retainPreviousSheet ? previousSheetEntry : null;
    final route = base.route;
    final searchOpen = route?.isGlobalSearch == true;
    final searchPage =
        (presentation != null
            ? presentation.searchRoute != null
            : searchIndex >= 0)
        ? ForumSearch.page(key: _searchPageKey)
        : null;
    final searchBehindSheet =
        searchPage != null &&
        !searchOpen &&
        base.previousRoute?.isGlobalSearch == true &&
        route != null &&
        (presentation?.usesSheet(route) ?? route.isTopic);
    final searchSource = presentation != null
        ? presentation.searchSourceRoute
        : searchIndex > 0
        ? stack[searchIndex - 1]
        : null;
    final source = presentation?.retainedListRoute;
    final covered =
        source != null &&
        base.sourceRoute == null &&
        route != null &&
        presentation!.usesSheet(route) &&
        stack.any(source.sameDestinationAs);
    final previous = mobilePresentation != null
        ? mobilePresentation.previousOf(route)
        : base.previousRoute;
    final livePrevious =
        !searchOpen &&
        !searchBehindSheet &&
        route != null &&
        base.sourceRoute == null &&
        shell.mobileNavigationEnabled &&
        (mobilePresentation?.usesSheet(route) ??
            (route.isTopic ||
                widget.registry.usesMobilePageSheet(context, route))) &&
        previous != null &&
        (mobilePresentation?.ownsChrome(previous) ??
            widget.registry.ownsContentChrome(context, previous)) &&
        !(mobilePresentation?.usesSheet(previous) ??
            widget.registry.usesMobilePageSheet(context, previous));
    final Widget? sheetUnderlay;
    if (searchBehindSheet) {
      sheetUnderlay = searchPage;
    } else if (livePrevious) {
      final previousBody = widget.builder(
        _MainContentSnapshot.forRoute(
          shell,
          tab,
          previous,
          previousRoute: mobilePresentation?.previousOf(previous),
        ),
        covered ? null : _sourceBodyKey,
        null,
        null,
      );
      sheetUnderlay = Builder(
        builder: (context) => DPageSurface(
          border: false,
          borderRadius: DSheetViewport.pageBorderRadius(context),
          backgroundColor: ForumWindowBackground.panelColor(context),
          depth: DSurfaceDepth.panel,
          child: previousBody,
        ),
      );
    } else {
      sheetUnderlay = null;
    }
    final primary = widget.builder(
      covered || searchOpen
          ? _MainContentSnapshot.forRoute(
              shell,
              tab,
              covered ? source : searchSource,
              previousRoute: presentation?.previousOf(
                covered ? source : searchSource,
              ),
            )
          : base,
      livePrevious && !covered ? null : _sourceBodyKey,
      covered ? null : sheetUnderlay,
      covered || searchOpen ? null : baseEntry,
    );
    final hidden = covered || searchOpen;
    final basePages = Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: hidden,
          child: ExcludeFocus(
            excluding: hidden,
            child: ExcludeSemantics(
              excluding: hidden,
              child: IgnorePointer(
                ignoring: hidden,
                child: ForumContentScope(
                  route: covered
                      ? source
                      : searchOpen
                      ? searchSource
                      : null,
                  child: hidden
                      ? DPageHeaderHost.exclude(child: primary)
                      : primary,
                ),
              ),
            ),
          ),
        ),
        if (covered && !searchOpen)
          widget.builder(base, null, sheetUnderlay, baseEntry),
        if (searchPage != null && !searchBehindSheet)
          Offstage(
            offstage: !searchOpen,
            child: ExcludeFocus(excluding: !searchOpen, child: searchPage),
          ),
      ],
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: retainPreviousSheet,
          child: TickerMode(
            enabled: !retainPreviousSheet,
            child: ExcludeFocus(
              excluding: retainPreviousSheet,
              child: DPageHeaderHost.exclude(
                excluding: retainPreviousSheet,
                child: basePages,
              ),
            ),
          ),
        ),
        if (retainPreviousSheet) widget.builder(current, null, null, null),
      ],
    );
  }
}
