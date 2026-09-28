import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../data/discover_sites.dart';
import '../models/discover_site.dart';
import '../theme/d_icons.dart';
import 'external_link.dart';
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
    final availableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    final textScaler = MediaQuery.textScalerOf(context);
    return Column(
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
        FutureBuilder<List<DiscoverSite>>(
          future: _load,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState != ConnectionState.done;
            if (!loading && snapshot.hasError) {
              return Padding(
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
              );
            }
            final sites = DiscoverSite.suggestions(
              snapshot.data ?? const [],
              added.map((site) => site.url),
            );
            if (!loading && sites.isEmpty) return const SizedBox.shrink();
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: (availableHeight - 300).clamp(120, 400),
              ),
              child: DScrollArea(
                thumbVisibility: false,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final columns =
                        constraints.maxWidth >= 480 &&
                            textScaler.scale(14) <= 21
                        ? 2
                        : 1;
                    final children = loading
                        ? List<Widget>.generate(
                            10,
                            (_) => const _SiteSkeleton(),
                          )
                        : [
                            for (final site in sites)
                              DItem(
                                key: ValueKey('discover-site-${site.url}'),
                                size: DItemSize.xs,
                                variant: DItemVariant.outline,
                                enabled: widget.enabled,
                                onPressed: () => widget.onSelected(site),
                                children: [
                                  DItemMedia(child: _SiteLogo(site: site)),
                                  DItemContent(
                                    children: [
                                      DItemTitle(
                                        maxLines: 2,
                                        child: Text(site.title),
                                      ),
                                      DItemDescription(
                                        maxLines: 1,
                                        child: Text(site.address),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                          ];
                    final grid = _SiteGrid(
                      columns: columns,
                      children: children,
                    );
                    return loading
                        ? DSkeletonRegion(
                            semanticsLabel:
                                context.l10n.loadingSuggestedCommunities,
                            color: skeletonFill(
                              context,
                              on: SkeletonSurface.floating,
                            ),
                            child: grid,
                          )
                        : grid;
                  },
                ),
              ),
            );
          },
        ),
        const SizedBox(height: DSpacing.md),
        Center(
          child: DButton(
            variant: DButtonVariant.link,
            label: Text(context.l10n.discoverMoreCommunities),
            icon: const DIcon(DIcons.upRightFromSquare, size: 12),
            iconPosition: DButtonIconPosition.end,
            onPressed: () => openExternalLink(DiscoverSites.browseUrl),
          ),
        ),
      ],
    );
  }
}

class _SiteGrid extends StatelessWidget {
  const _SiteGrid({required this.columns, required this.children});
  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var index = 0; index < children.length; index += columns) ...[
        if (index > 0) const SizedBox(height: DSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var column = 0; column < columns; column++) ...[
              if (column > 0) const SizedBox(width: DSpacing.sm),
              Expanded(
                child: index + column < children.length
                    ? children[index + column]
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ],
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
