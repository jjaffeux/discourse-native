import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../data/discover_site.dart';
import '../data/discover_sites.dart';
import '../foundation/icons/d_icons.dart';
import 'external_link.dart';
import 'image_decode.dart';
import 'shell_scope.dart';
import 'site_image.dart';
import 'skeleton_fill.dart';

class DiscoverSiteSuggestions extends StatefulWidget {
  const DiscoverSiteSuggestions({
    super.key,
    required this.source,
    required this.onSelected,
    this.enabled = true,
  });

  final DiscoverSites source;
  final ValueChanged<DiscoverSite> onSelected;
  final bool enabled;

  @override
  State<DiscoverSiteSuggestions> createState() =>
      _DiscoverSiteSuggestionsState();
}

class _DiscoverSiteSuggestionsState extends State<DiscoverSiteSuggestions> {
  late Future<List<DiscoverSite>> _load = widget.source.load();

  @override
  void didUpdateWidget(DiscoverSiteSuggestions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.source, oldWidget.source)) {
      _load = widget.source.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final added = ShellScope.maybeOf(context)?.instances ?? const [];
    final textScaler = MediaQuery.textScalerOf(context);
    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DSeparator(),
              const SizedBox(height: DSpacing.lg),
              Text(
                context.l10n.suggestedCommunities,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: tokens.mutedForeground),
              ),
              const SizedBox(height: DSpacing.md),
            ],
          ),
        ),
        FutureBuilder<List<DiscoverSite>>(
          future: _load,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState != ConnectionState.done;
            if (!loading && snapshot.hasError) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: DSpacing.lg),
                  child: Column(
                    children: [
                      Text(
                        context.l10n.suggestionsAreUnavailableRightNow,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens.mutedForeground,
                        ),
                      ),
                      const SizedBox(height: DSpacing.sm),
                      DButton(
                        variant: DButtonVariant.outline,
                        label: Text(context.l10n.tryAgain),
                        onPressed: () => setState(() {
                          _load = widget.source.load();
                        }),
                      ),
                    ],
                  ),
                ),
              );
            }
            final sites = DiscoverSite.suggestions(
              snapshot.data ?? const [],
              added.map((site) => site.url),
            );
            return SliverLayoutBuilder(
              builder: (context, constraints) {
                final columns =
                    constraints.crossAxisExtent >= 480 &&
                        textScaler.scale(14) <= 21
                    ? 2
                    : 1;
                final count = loading ? 10 : sites.length;
                final rows = (count + columns - 1) ~/ columns;

                Widget row(int index) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var column = 0; column < columns; column++) ...[
                      if (column > 0) const SizedBox(width: DSpacing.sm),
                      Expanded(
                        child: switch (index * columns + column) {
                          final item when item >= count =>
                            const SizedBox.shrink(),
                          _ when loading => const _SiteSkeleton(),
                          final item => _siteItem(sites[item]),
                        },
                      ),
                    ],
                  ],
                );

                if (loading) {
                  return SliverToBoxAdapter(
                    child: DSkeletonRegion(
                      semanticsLabel: context.l10n.loadingSuggestedCommunities,
                      color: skeletonFill(
                        context,
                        on: SkeletonSurface.floating,
                      ),
                      child: Column(
                        children: [
                          for (var index = 0; index < rows; index++) ...[
                            if (index > 0) const SizedBox(height: DSpacing.sm),
                            row(index),
                          ],
                        ],
                      ),
                    ),
                  );
                }
                return SliverList.separated(
                  itemCount: rows,
                  itemBuilder: (_, index) => row(index),
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: DSpacing.sm),
                );
              },
            );
          },
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: DSpacing.md),
            child: Center(
              child: DButton(
                variant: DButtonVariant.link,
                label: Text(context.l10n.discoverMoreCommunities),
                icon: const DIcon(DIcons.upRightFromSquare, size: 12),
                iconPosition: DButtonIconPosition.end,
                onPressed: () => openExternalLink(DiscoverSites.browseUrl),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _siteItem(DiscoverSite site) => DItem(
    key: ValueKey('discover-site-${site.url}'),
    size: DItemSize.xs,
    variant: DItemVariant.outline,
    enabled: widget.enabled,
    onPressed: () => widget.onSelected(site),
    children: [
      DItemMedia(child: _SiteLogo(site: site)),
      DItemContent(
        children: [
          DItemTitle(maxLines: 2, child: Text(site.title)),
          DItemDescription(maxLines: 1, child: Text(site.address)),
        ],
      ),
    ],
  );
}

class _SiteSkeleton extends StatelessWidget {
  const _SiteSkeleton();

  @override
  Widget build(BuildContext context) => const DItem(
    size: DItemSize.xs,
    variant: DItemVariant.outline,
    children: [
      DItemMedia(child: DSkeleton(width: 32, height: 32)),
      DItemContent(
        spacing: DSpacing.sm,
        children: [
          FractionallySizedBox(widthFactor: .85, child: DSkeleton(height: 16)),
          FractionallySizedBox(widthFactor: .65, child: DSkeleton(height: 12)),
        ],
      ),
    ],
  );
}

class _SiteLogo extends StatelessWidget {
  const _SiteLogo({required this.site});
  final DiscoverSite site;

  @override
  Widget build(BuildContext context) {
    final fallback = DAvatarFallback(child: Text(site.title.characters.first));
    return DAvatar(
      decorative: true,
      borderRadius: BorderRadius.circular(DRadius.panel),
      child: site.logoUrl == null
          ? fallback
          : SiteImage(
              url: site.logoUrl!,
              siteUrl: null,
              fit: BoxFit.contain,
              // Height only: the exact-size resize policy would stretch a
              // non-square logo if both axes were bound.
              cacheHeight: imagePhysicalPixels(context, 32),
              excludeFromSemantics: true,
              loadingBuilder: (_) => DSkeleton(
                width: 32,
                height: 32,
                color: skeletonFill(context, on: SkeletonSurface.floating),
              ),
              errorBuilder: (_, _, _) => fallback,
            ),
    );
  }
}
