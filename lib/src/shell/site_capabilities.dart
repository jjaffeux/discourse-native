import 'dart:async';

import '../data/site_lifecycle.dart';
import '../data/topic_composer_queries_api.dart';
import '../data/write_credential.dart';
import '../models/post_flag.dart';
import '../models/topic.dart';

final class _ComposerCapabilityRead {
  _ComposerCapabilityRead(this.lease);

  /// The account this read speaks for. A successor at the same URL holds a
  /// different lease, so it never joins this read or accepts its answer.
  final SiteLease lease;

  final Completer<void> settled = Completer<void>();
}

final class _SiteCapabilityRecord {
  TopicComposerCapabilities? composer;
  SitePostActionCatalog? postActions;
  Set<String> serverPluginNames = const {};
  _ComposerCapabilityRead? composerRead;
}

/// What each forum lets this account do, as far as the app has learned it.
/// Retiring a site is one removal.
final class SiteCapabilities {
  SiteCapabilities({
    required this.credentialForWrite,
    required this.topicComposerQueries,
    required this.lifecycle,
    required this.changed,
  });

  final Future<WriteCredential> Function(
    String siteUrl, {
    required SiteLease lease,
  })
  credentialForWrite;
  final TopicComposerQueriesApi topicComposerQueries;
  final SiteLifecycle lifecycle;
  final void Function() changed;

  final Map<String, _SiteCapabilityRecord> _sites = {};

  _SiteCapabilityRecord _site(String siteUrl) =>
      _sites.putIfAbsent(siteUrl, _SiteCapabilityRecord.new);

  TopicComposerCapabilities composer(String siteUrl) =>
      _sites[siteUrl]?.composer ?? const TopicComposerCapabilities();

  SitePostActionCatalog postActions(String siteUrl) =>
      _sites[siteUrl]?.postActions ?? const SitePostActionCatalog();

  bool hasServerPlugin(String siteUrl, String name) =>
      _sites[siteUrl]?.serverPluginNames.contains(name) ?? false;

  /// Settles once this account's read has answered or failed. A failed read
  /// leaves nothing held, so the next caller asks again.
  Future<void> ensureComposer(String siteUrl) {
    final site = _site(siteUrl);
    if (site.composer != null) return Future.value();
    if (site.composerRead case final read? when read.lease.isCurrent) {
      return read.settled.future;
    }
    final read = _ComposerCapabilityRead(lifecycle.capture(siteUrl));
    site.composerRead = read;
    unawaited(_readComposer(siteUrl, read));
    return read.settled.future;
  }

  Future<void> _readComposer(
    String siteUrl,
    _ComposerCapabilityRead read,
  ) async {
    final lease = read.lease;
    try {
      final credential = await credentialForWrite(siteUrl, lease: lease);
      if (!lease.isCurrent || credential.failure != null) return;
      final capabilities = await credential.request!.run(
        () => topicComposerQueries.topicComposerCapabilities(
          siteUrl: siteUrl,
          apiKey: credential.apiKey!,
        ),
      );
      lease.commit(() {
        _site(siteUrl).composer = capabilities;
        changed();
      });
    } catch (_) {
    } finally {
      // A successor may have replaced this read while it was out.
      final site = _sites[siteUrl];
      if (identical(site?.composerRead, read)) site!.composerRead = null;
      read.settled.complete();
    }
  }

  /// Runs inside the category read's own lease commit, whose caller notifies.
  ///
  /// A composer read that settled during the category read is newer, so a
  /// held composer answer stands. One still out overwrites this seed.
  void acceptCategoryRead(
    String siteUrl, {
    required SitePostActionCatalog? postActions,
    required TopicComposerCapabilities? composer,
  }) {
    final site = _site(siteUrl);
    if (postActions != null) site.postActions = postActions;
    site.composer ??= composer;
  }

  void acceptServerPlugins(String siteUrl, Set<String> names) {
    _site(siteUrl).serverPluginNames = names;
    changed();
  }

  void forget(String siteUrl) {
    _sites.remove(siteUrl);
  }
}
