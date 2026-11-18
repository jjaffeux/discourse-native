part of 'main_content.dart';

class _MobilePageSheet extends StatelessWidget {
  const _MobilePageSheet({
    required this.route,
    required this.entry,
    required this.viewportKey,
    required this.reader,
    required this.underlay,
    this.readerKey,
    this.covering,
    this.opaqueUnderlayCard = false,
  });

  final ContentRoute route;
  final Object entry;
  final Key viewportKey;
  final Key? readerKey;
  final Widget? reader;
  final Widget? underlay;
  final ValueNotifier<bool>? covering;
  final bool opaqueUnderlayCard;

  static final _visitStorage = Expando<PageStorageBucket>();

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.read(context);
    final page = reader;
    return DSheetViewport(
      key: viewportKey,
      covering: covering,
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
      opaqueUnderlayCard: opaqueUnderlayCard,
      content: page == null
          ? null
          : DSheetContent(
              key: readerKey,
              side: DSheetSide.bottom,
              variant: DSheetVariant.page,
              showCloseButton: false,
              semanticLabel: route.title,
              backgroundColor: ForumWindowBackground.panelColor(context),
              children: [
                Expanded(
                  child: route.destination is ExtensionDestination
                      ? PluginUiScope.withVisitStorage(
                          _visitStorage[entry] ??= PageStorageBucket(),
                          page,
                        )
                      : page,
                ),
              ],
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
  final Widget Function(
    _MainContentSnapshot,
    Key?, {
    Widget? underlay,
    Object? sheetEntry,
    ValueNotifier<bool>? covering,
  })
  builder;

  @override
  State<_MobileContentHost> createState() => _MobileContentHostState();
}

class _MobileContentHostState extends State<_MobileContentHost> {
  final _sourceBodyKey = GlobalKey();
  var _searchPageKey = GlobalKey();
  final _readerCovering = ValueNotifier(false);
  final _searchCovered = FrameSafeValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _readerCovering.addListener(_syncSearchCover);
  }

  void _syncSearchCover() => _searchCovered.value = _readerCovering.value;

  @override
  void dispose() {
    _readerCovering.dispose();
    _searchCovered.dispose();
    super.dispose();
  }

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
        (currentRoute?.isTopic == true ||
            currentRoute?.destination is ExtensionDestination) &&
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
    final searchBehindTopic =
        searchBehindSheet && presentation?.topicOverSearch == true;
    final searchSource = presentation != null
        ? presentation.searchSourceRoute
        : searchIndex > 0
        ? stack[searchIndex - 1]
        : null;
    final searchPreview =
        searchOpen &&
            searchSource != null &&
            presentation?.usesSheet(searchSource) == true
        ? DHistoryTransition.previousPageUnderlayOf(context)
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
    if (searchBehindTopic) {
      sheetUnderlay = const SizedBox.expand();
    } else if (searchBehindSheet) {
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
      underlay: covered ? null : sheetUnderlay,
      sheetEntry: searchOpen
          ? previousSheetEntry
          : covered
          ? null
          : baseEntry,
      covering: searchBehindTopic ? _readerCovering : null,
    );
    final hidden = covered || searchOpen;
    final sourcePage = Offstage(
      offstage:
          covered ||
          searchOpen && (searchSource == null || searchPreview != null),
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
                  ? DPageHeaderHost.exclude(
                      child: searchOpen
                          ? Padding(
                              padding: EdgeInsets.only(
                                top:
                                    DSheetDragScope.topBarExtentOf(context) +
                                    mobilePageTopGap,
                              ),
                              child: TickerMode(enabled: false, child: primary),
                            )
                          : primary,
                    )
                  : searchBehindTopic
                  ? Padding(
                      padding: const EdgeInsets.only(top: mobileRaisedPageTop),
                      child: primary,
                    )
                  : primary,
            ),
          ),
        ),
      ),
    );
    final Widget? searchLayer;
    if (searchPage == null || searchBehindSheet && !searchBehindTopic) {
      searchLayer = null;
    } else {
      final pull = DSheetDragScope.dismissProgressOf(context);
      final animateEntrance =
          searchBehindTopic &&
          !MediaQuery.disableAnimationsOf(context) &&
          DHistoryTransition.shouldAnimatePageEntranceOf(context);
      // Keep the last Search frame visible while the live sheet processes the
      // keyboard hide. Pulling the topic down reveals the live, settled sheet.
      final departure = animateEntrance
          ? DHistoryTransition.previousPageUnderlayOf(context)
          : null;
      searchLayer = DSheetBackdrop(
        key: const ValueKey('mobile-search-layer'),
        covered: searchBehindTopic,
        surfaceIdentity: shell.mobileNavigation.entryId,
        child: ListenableBuilder(
          listenable: Listenable.merge([_searchCovered, pull]),
          child: ExcludeFocus(
            excluding: !searchOpen,
            child: ExcludeSemantics(
              excluding: !searchOpen,
              child: IgnorePointer(ignoring: !searchOpen, child: searchPage),
            ),
          ),
          builder: (context, search) {
            final pulling = (pull?.value ?? 0) > 0;
            final visible =
                searchOpen ||
                searchBehindTopic &&
                    (pulling || animateEntrance && !_searchCovered.value);
            final preview = visible && !pulling ? departure : null;
            return Stack(
              fit: StackFit.expand,
              children: [
                Offstage(offstage: !visible || preview != null, child: search),
                ?preview,
              ],
            );
          },
        ),
      );
    }
    final basePages = Stack(
      fit: StackFit.expand,
      children: [
        if (searchBehindTopic) ?searchLayer,
        Stack(fit: StackFit.expand, children: [sourcePage, ?searchPreview]),
        if (covered && !searchOpen)
          widget.builder(
            base,
            null,
            underlay: sheetUnderlay,
            sheetEntry: baseEntry,
          ),
        if (!searchBehindTopic) ?searchLayer,
      ],
    );
    final previousSheetPreview = retainPreviousSheet
        ? DHistoryTransition.previousPageUnderlayOf(context)
        : null;
    final useLiveUnderlay = retainPreviousSheet && previousSheetPreview == null;
    // The topic rises over the bar. A hidden live page still needs its original
    // viewport behind the snapshot so its scroll bounds stay the same.
    final retainedTopInset =
        previousSheetPreview != null && currentRoute?.isTopic == true
        ? (DSheetDragScope.topBarExtentOf(context) +
                  mobilePageTopGap -
                  mobileRaisedPageTop)
              .clamp(0.0, double.infinity)
        : 0.0;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!useLiveUnderlay)
          Offstage(
            offstage: retainPreviousSheet,
            child: TickerMode(
              enabled: !retainPreviousSheet,
              child: ExcludeFocus(
                excluding: retainPreviousSheet,
                child: DPageHeaderHost.exclude(
                  excluding: retainPreviousSheet,
                  child: Padding(
                    padding: EdgeInsets.only(top: retainedTopInset),
                    child: basePages,
                  ),
                ),
              ),
            ),
          ),
        if (retainPreviousSheet)
          widget.builder(
            current,
            null,
            underlay:
                previousSheetPreview ??
                // The underlay's tickers are muted while it is covered.
                MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(disableAnimations: true),
                  child: basePages,
                ),
          ),
      ],
    );
  }
}
