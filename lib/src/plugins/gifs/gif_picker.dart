import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../plugin_api/core_plugin_host.dart';
import '../../shell/image_decode.dart';
import '../../shell/shell_sheet.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'gif.dart';
import 'gif_picker_controller.dart';
import 'gifs_api.dart';
import 'gifs_settings.dart';

/// Opens the shared GIF browser and returns the chosen remote image.
///
/// This surface deliberately knows nothing about either composer. Topic and
/// chat callers decide whether a returned GIF should be inserted, sent, or
/// discarded because their draft changed while the picker was open.
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
    final touch = switch (Theme.of(context).platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
    if (touch) {
      return await showShellSheet<GifResult>(
        context: context,
        title: 'Search GIFs',
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        builder: (sheetContext) => SizedBox(
          height: _pickerHeight(sheetContext),
          child: GifPicker(
            controller: controller,
            siteUrl: siteUrl,
            onPicked: Navigator.of(sheetContext).pop,
          ),
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
              const Divider(height: 1),
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
          child: Text(
            'Search GIFs',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          key: const ValueKey('gif-picker-close'),
          onPressed: onClose,
          icon: const DIcon(DIcons.xmark),
          tooltip: 'Close',
        ),
      ],
    ),
  );
}

/// Search field, result grid, and attribution shared by sheet and dialog.
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
    if (!_resultsScroll.hasClients ||
        _resultsScroll.position.extentAfter > 320) {
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
        builder: (context, _) => TextField(
          key: const ValueKey('gif-picker-search'),
          controller: _search,
          focusNode: _searchFocus,
          autofocus: true,
          inputFormatters: [LengthLimitingTextInputFormatter(100)],
          textInputAction: TextInputAction.search,
          onChanged: widget.controller.updateQuery,
          decoration: InputDecoration(
            hintText: 'Search GIFs',
            prefixIcon: const Padding(
              padding: EdgeInsets.all(13),
              child: DIcon(DIcons.magnifyingGlass, size: 18),
            ),
            suffixIcon: _searchSuffix(),
            border: const OutlineInputBorder(),
          ),
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
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_search.text.isEmpty) return null;
    return IconButton(
      key: const ValueKey('gif-picker-clear'),
      onPressed: () {
        _search.clear();
        widget.controller.updateQuery('');
        _searchFocus.requestFocus();
      },
      icon: const DIcon(DIcons.xmark, size: 16),
      tooltip: 'Clear search',
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
                onPicked: widget.onPicked,
              ),
            ),
          ),
          if (controller.loadingMore || controller.canLoadMore)
            Center(
              child: controller.loadingMore
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : TextButton(
                      key: const ValueKey('gif-picker-load-more'),
                      onPressed: controller.loadMore,
                      child: const Text('Load more'),
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
        action: FilledButton.tonal(
          key: const ValueKey('gif-picker-retry'),
          onPressed: controller.retry,
          child: const Text('Try again'),
        ),
      );
    }

    if (controller.showingCategories) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Browse categories',
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
      return const Center(child: CircularProgressIndicator());
    }

    if (!controller.hasActiveSearch) {
      return const _PickerMessage(
        icon: DIcons.gif,
        message: 'Type at least 3 characters to search for a GIF.',
      );
    }

    return const _PickerMessage(
      icon: DIcons.magnifyingGlass,
      message: 'No GIFs found.',
    );
  }
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
        ? 'Choose GIF'
        : 'Choose ${result.title} GIF';
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: Material(
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: InkWell(
            onTap: () => onPicked(result),
            child: _NetworkArtwork(url: result.url, fit: BoxFit.cover),
          ),
        ),
      ),
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
    label: 'Search ${category.title} GIFs',
    child: Tooltip(
      message: 'Search ${category.title} GIFs',
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
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.errorContainer,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              container: true,
              liveRegion: true,
              child: Text(
                message,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
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
    child: Padding(
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
    final base = siteUrl.replaceFirst(RegExp(r'/+$'), '');
    final url = '$base/images/klipy-logo${dark ? '-dark' : ''}.png';
    return Align(
      key: const ValueKey('gif-picker-attribution'),
      alignment: Alignment.centerRight,
      child: Semantics(
        label: 'Powered by Klipy',
        image: true,
        child: SizedBox(
          height: 30,
          child: Image.network(
            url,
            excludeFromSemantics: true,
            fit: BoxFit.contain,
            cacheHeight: imagePhysicalPixels(context, 30),
            errorBuilder: (context, _, _) => Text(
              'Powered by Klipy',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ),
      ),
    );
  }
}
