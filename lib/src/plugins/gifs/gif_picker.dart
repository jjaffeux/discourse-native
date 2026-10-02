import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'gif.dart';
import 'gif_picker_controller.dart';
import 'gifs_api.dart';
import 'gifs_icons.dart';
import 'gifs_settings.dart';

final RegExp _trailingSlashes = RegExp(r'/+$');

/// Callers own draft-staleness checks and insertion of the returned GIF.
Future<GifResult?> showGifPicker({
  required BuildContext context,
  required String siteUrl,
  required GifsApi api,
  required PluginRequestHost requests,
  required GifsSettings settings,
}) async {
  final controller = GifPickerController(
    siteUrl: siteUrl,
    api: api,
    requests: requests,
    fileDetail: settings.fileDetail,
    maxResults: settings.resultLimitEnabled ? settings.maxResults : null,
  );
  unawaited(controller.loadCategories());

  try {
    if (context.isTouch) {
      return await showDSheet<GifResult>(
        context: context,
        side: DSheetSide.bottom,
        inset: true,
        fillAvailableHeight: true,
        builder: (context, sheet) => DSheetContent(
          side: DSheetSide.bottom,
          semanticLabel: appL10n.searchGIFs,
          topBottomMaxHeightFactor: 1,
          scrollWholeSheet: false,
          showCloseButton: false,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ComposerSheetHeader(
                    title: context.l10n.searchGIFs,
                    closeButtonKey: const ValueKey('gif-picker-close'),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DSpacing.lg,
                        vertical: DSpacing.sm,
                      ),
                      child: GifPicker(
                        controller: controller,
                        siteUrl: siteUrl,
                        onPicked: sheet.close,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return await showDialog<GifResult>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: SizedBox(
          width: 620,
          height: _pickerHeight(dialogContext),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DialogHeader(onClose: () => Navigator.of(dialogContext).pop()),
              const DSeparator(space: 1),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: GifPicker(
                    controller: controller,
                    siteUrl: siteUrl,
                    onPicked: Navigator.of(dialogContext).pop,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  } finally {
    controller.dispose();
  }
}

double _pickerHeight(BuildContext context) =>
    (MediaQuery.sizeOf(context).height * 0.7).clamp(360.0, 540.0).toDouble();

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: DText(
            context.l10n.searchGIFs,
            variant: DTextVariant.h4,
            headingLevel: 1,
          ),
        ),
        DButton.iconOnly(
          key: const ValueKey('gif-picker-close'),
          onPressed: onClose,
          variant: DButtonVariant.ghost,
          tooltip: context.l10n.close,
          icon: const DIcon(DIcons.xmark),
        ),
      ],
    ),
  );
}

class GifPicker extends StatefulWidget {
  const GifPicker({
    super.key,
    required this.controller,
    required this.siteUrl,
    required this.onPicked,
  });

  final GifPickerController controller;
  final String siteUrl;
  final ValueChanged<GifResult> onPicked;

  @override
  State<GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends State<GifPicker> {
  late final TextEditingController _search;
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _resultsScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.controller.query);
    _resultsScroll.addListener(_maybeLoadMore);
  }

  void _maybeLoadMore() {
    // A failed page waits for Try again or Load more. Re-requesting it on
    // every scroll tick would prolong a rate limit and re-announce the error.
    if (widget.controller.error != null ||
        !_resultsScroll.hasClients ||
        _resultsScroll.position.extentAfter >
            paginationPrefetchDistance(_resultsScroll.position)) {
      return;
    }
    unawaited(widget.controller.loadMore());
  }

  @override
  void dispose() {
    _resultsScroll
      ..removeListener(_maybeLoadMore)
      ..dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => DInput(
          key: const ValueKey('gif-picker-search'),
          controller: _search,
          focusNode: _searchFocus,
          autofocus: true,
          inputFormatters: [LengthLimitingTextInputFormatter(100)],
          textInputAction: TextInputAction.search,
          onChanged: widget.controller.updateQuery,
          hintText: context.l10n.searchGIFs,
          prefix: const DIcon(DIcons.magnifyingGlass, size: 16),
          suffix: _searchSuffix(),
        ),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => _buildContent(context),
        ),
      ),
      const SizedBox(height: 8),
      _KlipyAttribution(siteUrl: widget.siteUrl),
    ],
  );

  Widget? _searchSuffix() {
    final controller = widget.controller;
    if (controller.searching || controller.searchPending) {
      return null;
    }
    if (_search.text.isEmpty) return null;
    return DButton.iconOnly(
      key: const ValueKey('gif-picker-clear'),
      onPressed: () {
        _search.clear();
        widget.controller.updateQuery('');
        _searchFocus.requestFocus();
      },
      variant: DButtonVariant.ghost,
      tooltip: appL10n.clearSearch,
      icon: const DIcon(DIcons.xmark),
    );
  }

  Widget _buildContent(BuildContext context) {
    final controller = widget.controller;
    if (controller.results.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.error case final error?)
            _InlineError(message: error, onRetry: controller.retry),
          Expanded(
            child: GridView.builder(
              key: const ValueKey('gif-picker-results'),
              controller: _resultsScroll,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: controller.results.length,
              itemBuilder: (context, index) => _GifResultTile(
                key: ValueKey('gif-result-$index'),
                result: controller.results[index],
                onPicked: (result) {
                  if (controller.isCurrent &&
                      controller.results.contains(result)) {
                    widget.onPicked(result);
                  }
                },
              ),
            ),
          ),
          if (controller.loadingMore || controller.canLoadMore)
            Center(
              child: controller.loadingMore
                  ? DSkeletonRegion(
                      key: const ValueKey('gif-picker-page-loading'),
                      semanticsLabel: context.l10n.loading,
                      color: skeletonFill(
                        context,
                        on: SkeletonSurface.floating,
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: DSpacing.sm),
                        child: DSkeleton(width: 96, height: 20),
                      ),
                    )
                  : DButton(
                      key: const ValueKey('gif-picker-load-more'),
                      label: Text(context.l10n.loadMore),
                      onPressed: controller.loadMore,
                      variant: DButtonVariant.link,
                    ),
            ),
        ],
      );
    }

    if (controller.error case final error?) {
      return _PickerMessage(
        icon: DIcons.triangleExclamation,
        message: error,
        liveRegion: true,
        action: DButton(
          key: const ValueKey('gif-picker-retry'),
          label: Text(context.l10n.tryAgain),
          onPressed: controller.retry,
        ),
      );
    }

    if (controller.showingCategories) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.browseCategories,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              key: const ValueKey('gif-picker-categories'),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 4 / 3,
              ),
              itemCount: controller.categories.length,
              itemBuilder: (context, index) {
                final category = controller.categories[index];
                return _GifCategoryTile(
                  key: ValueKey('gif-category-$index'),
                  category: category,
                  onPicked: () {
                    _search.value = TextEditingValue(
                      text: category.searchTerm,
                      selection: TextSelection.collapsed(
                        offset: category.searchTerm.length,
                      ),
                    );
                    _searchFocus.requestFocus();
                    unawaited(controller.selectCategory(category));
                  },
                );
              },
            ),
          ),
        ],
      );
    }

    if (controller.isBusy || controller.searchPending) {
      return _GifGridSkeleton(categories: !controller.hasActiveSearch);
    }

    if (!controller.hasActiveSearch) {
      return _PickerMessage(
        icon: GifsIcons.gif,
        message: context.l10n.typeAtLeast3CharactersToSearchForAGIF,
      );
    }

    return _PickerMessage(
      icon: DIcons.magnifyingGlass,
      message: context.l10n.noGIFsFound,
    );
  }
}

class _GifGridSkeleton extends StatelessWidget {
  const _GifGridSkeleton({required this.categories});

  final bool categories;

  @override
  Widget build(BuildContext context) => DSkeletonRegion(
    key: const ValueKey('gif-picker-loading'),
    semanticsLabel: categories
        ? context.l10n.loadingCategories
        : context.l10n.searching,
    color: skeletonFill(context, on: SkeletonSurface.floating),
    expand: true,
    child: LayoutBuilder(
      builder: (context, constraints) {
        const spacing = DSpacing.sm;
        final columns = math.max(
          1,
          (constraints.maxWidth / ((categories ? 200 : 180) + spacing)).ceil(),
        );
        final width =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;
        final height = width / (categories ? 4 / 3 : 1);
        final rows = math.max(
          1,
          (constraints.maxHeight / (height + spacing)).ceil(),
        );
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            maxHeight: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var row = 0; row < rows; row++) ...[
                  if (row > 0) const SizedBox(height: spacing),
                  Row(
                    children: [
                      for (var column = 0; column < columns; column++) ...[
                        if (column > 0) const SizedBox(width: spacing),
                        Expanded(child: DSkeleton(height: height)),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _GifResultTile extends StatelessWidget {
  const _GifResultTile({
    super.key,
    required this.result,
    required this.onPicked,
  });

  final GifResult result;
  final ValueChanged<GifResult> onPicked;

  @override
  Widget build(BuildContext context) {
    final label = result.title.trim().isEmpty
        ? context.l10n.chooseGIF
        : context.l10n.chooseGIFGifpicker((result.title).toString());
    return DButton(
      onPressed: () => onPicked(result),
      variant: DButtonVariant.secondary,
      semanticLabel: label,
      tooltip: label,
      label: _NetworkArtwork(url: result.url, fit: BoxFit.cover),
    );
  }
}

class _GifCategoryTile extends StatelessWidget {
  const _GifCategoryTile({
    super.key,
    required this.category,
    required this.onPicked,
  });

  final GifCategory category;
  final VoidCallback onPicked;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: context.l10n.searchGIFsGifpicker((category.title).toString()),
    child: DTooltip(
      message: context.l10n.searchGIFsGifpicker((category.title).toString()),
      excludeFromSemantics: true,
      child: Material(
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: InkWell(
          onTap: onPicked,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _NetworkArtwork(url: category.imageUrl, fit: BoxFit.cover),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xB3000000)],
                    stops: [0.45, 1],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    category.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _NetworkArtwork extends StatelessWidget {
  const _NetworkArtwork({required this.url, required this.fit});

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Image(
      image: _provider(context, constraints),
      excludeFromSemantics: true,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (context, _, _) => Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );

  ImageProvider<Object> _provider(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final provider = NetworkImage(url);
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      return provider;
    }
    // A fit bound would shrink the long side to the tile, and cover would
    // then scale the short side back up past its decoded pixels.
    if (fit == BoxFit.cover) {
      return imageForCover(context, provider, logicalSize: Size(width, height));
    }
    return ResizeImage(
      provider,
      width: imagePhysicalPixels(context, width),
      height: imagePhysicalPixels(context, height),
      policy: ResizeImagePolicy.fit,
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => DAlert(
    variant: DAlertVariant.destructive,
    description: DAlertDescription(child: Text(message)),
    action: DAlertAction(
      child: DButton(
        label: Text(context.l10n.tryAgain),
        onPressed: onRetry,
        variant: DButtonVariant.link,
      ),
    ),
  );
}

class _PickerMessage extends StatelessWidget {
  const _PickerMessage({
    required this.icon,
    required this.message,
    this.action,
    this.liveRegion = false,
  });

  final DIconData icon;
  final String message;
  final Widget? action;
  final bool liveRegion;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DIcon(
            icon,
            size: 28,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          if (liveRegion)
            Semantics(
              container: true,
              liveRegion: true,
              child: Text(message, textAlign: TextAlign.center),
            )
          else
            Text(message, textAlign: TextAlign.center),
          if (action case final action?) ...[
            const SizedBox(height: 12),
            action,
          ],
        ],
      ),
    ),
  );
}

class _KlipyAttribution extends StatelessWidget {
  const _KlipyAttribution({required this.siteUrl});

  final String siteUrl;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = siteUrl.replaceFirst(_trailingSlashes, '');
    final url = '$base/images/klipy-logo${dark ? '-dark' : ''}.png';
    return Align(
      key: const ValueKey('gif-picker-attribution'),
      alignment: Alignment.centerRight,
      child: Semantics(
        label: context.l10n.poweredByKlipy,
        image: true,
        child: SizedBox(
          height: 30,
          child: Image.network(
            url,
            excludeFromSemantics: true,
            fit: BoxFit.contain,
            cacheHeight: imagePhysicalPixels(context, 30),
            errorBuilder: (context, _, _) => Text(
              context.l10n.poweredByKlipy,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
      ),
    );
  }
}
