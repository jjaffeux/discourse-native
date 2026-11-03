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
    required this.builder,
  });

  final Object owner;
  final _MainContentSnapshot state;
  final Widget Function(_MainContentSnapshot, Key?, Widget?) builder;

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
    final presentation = ForumTabScope.panelOf(context) == null
        ? MobilePresentationScope.maybeOf(context)
        : null;
    final stack = tab.contentStack;
    final searchIndex = stack.lastIndexWhere((route) => route.isGlobalSearch);
    final route = widget.state.route;
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
        widget.state.previousRoute?.isGlobalSearch == true &&
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
        widget.state.sourceRoute == null &&
        widget.state.route != null &&
        presentation!.usesSheet(widget.state.route!) &&
        stack.any(source.sameDestinationAs);
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
          : widget.state,
      _sourceBodyKey,
      searchBehindSheet ? searchPage : null,
    );
    final hidden = covered || searchOpen;
    return Stack(
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
        if (covered && !searchOpen) widget.builder(widget.state, null, null),
        if (searchPage != null && !searchBehindSheet)
          Offstage(
            offstage: !searchOpen,
            child: ExcludeFocus(excluding: !searchOpen, child: searchPage),
          ),
      ],
    );
  }
}
