import 'dart:async';

import '../data/content_snapshot_store.dart';
import '../data/discourse_topic_api.dart';
import '../data/site_lifecycle.dart';
import '../data/wire_body.dart';
import '../models/discourse_instance.dart';
import '../models/discourse_model_codec.dart';
import '../models/post.dart';
import '../models/topic.dart';

/// What the feed and topic loaders may ask of the last launch.
///
/// Every answer is stale by definition. A loader publishes one only where no
/// response has landed, and always goes on to ask the site.
abstract interface class FeedSnapshots {
  Future<TopicList?> feed(
    String siteUrl,
    SiteLease lease,
    String destinationId,
    String path,
  );

  void rememberFeed(
    String siteUrl,
    SiteLease lease,
    String destinationId,
    String path,
    TopicList list,
  );
}

abstract interface class TopicSnapshots {
  Future<TopicPayload?> topic(String siteUrl, SiteLease lease, int topicId);

  void rememberTopic(String siteUrl, SiteLease lease, TopicPayload payload);
}

/// Binds the snapshot file to the account that may read it.
///
/// The store knows accounts only as strings. This owner decides which string
/// a request speaks for, and refuses both directions once that account's
/// lease has retired: a read begun before sign-out answers nothing, and a
/// response that outlived its account is not written down.
final class ContentSnapshots implements FeedSnapshots, TopicSnapshots {
  ContentSnapshots({
    required this._store,
    required this._models,
    required this._lifecycle,
    required this._instanceAt,
  });

  final ContentSnapshotStore _store;
  final DiscourseModelCodec _models;
  final SiteLifecycle _lifecycle;
  final DiscourseInstance? Function(String siteUrl) _instanceAt;

  /// Null where the forum has nothing its reader may see: it left the rail,
  /// or it requires a login nobody has given.
  static String? accountOf(DiscourseInstance? instance) {
    if (instance == null) return null;
    final user = instance.user;
    if (user == null) return instance.loginRequired ? null : 'anonymous';
    final id = user.id;
    return id != null && id > 0
        ? 'id:$id'
        : 'username:${user.username.toLowerCase()}';
  }

  String? _account(String siteUrl, SiteLease lease) =>
      lease.isCurrent && _lifecycle.owns(siteUrl, lease)
      ? accountOf(_instanceAt(siteUrl))
      : null;

  @override
  Future<TopicList?> feed(
    String siteUrl,
    SiteLease lease,
    String destinationId,
    String path,
  ) => _read(
    siteUrl,
    lease,
    (account) => _store.readFeed(siteUrl, account, destinationId, path),
    (wire) => decodeTopicListWire(_models, wire, siteUrl),
  );

  @override
  Future<TopicPayload?> topic(String siteUrl, SiteLease lease, int topicId) =>
      _read(
        siteUrl,
        lease,
        (account) => _store.readTopic(siteUrl, account, topicId),
        (wire) => decodeTopicWire(_models, wire, siteUrl),
      );

  Future<T?> _read<T>(
    String siteUrl,
    SiteLease lease,
    Future<String?> Function(String account) read,
    Future<T> Function(String wire) decode,
  ) async {
    final account = _account(siteUrl, lease);
    if (account == null) return null;
    try {
      final wire = await read(account);
      if (wire == null || _account(siteUrl, lease) != account) return null;
      final value = await decode(wire);
      return _account(siteUrl, lease) == account ? value : null;
    } catch (_) {
      // The parsers answer defaults for a payload they half recognise, so
      // this is a body that is no longer JSON. It is the same as no snapshot.
      return null;
    }
  }

  @override
  void rememberFeed(
    String siteUrl,
    SiteLease lease,
    String destinationId,
    String path,
    TopicList list,
  ) {
    final body = WireBody.from(list);
    final account = _account(siteUrl, lease);
    if (body == null || account == null) return;
    _store.saveFeed(
      siteUrl,
      account,
      destinationId,
      path,
      wire: body.text,
      bytes: body.byteLength,
    );
  }

  @override
  void rememberTopic(String siteUrl, SiteLease lease, TopicPayload payload) {
    final body = WireBody.from(payload.detail);
    final account = _account(siteUrl, lease);
    if (body == null || account == null) return;
    _store.saveTopic(
      siteUrl,
      account,
      payload.detail.id,
      wire: body.text,
      bytes: body.byteLength,
    );
  }

  /// Deletes the forum's snapshot. Called wherever an account's state is
  /// dropped: sign-out, an account change, and the forum leaving the rail.
  void forget(String siteUrl) => unawaited(_store.forget(siteUrl));

  void flush() => unawaited(_store.flush());
}
