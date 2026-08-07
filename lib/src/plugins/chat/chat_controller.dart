import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../data/authenticator.dart';
import '../../data/discourse_api.dart';
import '../../data/store.dart';
import 'chat_channel.dart';
import 'chat_message.dart';

/// What the main region knows about one channel, at one moment.
///
/// The sibling of `TopicFeed`, and ids rather than messages for the same
/// reason: the messages themselves are in the [Store], where one copy is shared
/// by the row drawing it and anything else that names it, so this is only the
/// order they go in.
@immutable
class ChatStreamState {
  const ChatStreamState({
    this.messageIds = const [],
    this.loading = false,
    this.loadingOlder = false,
    this.canLoadMorePast = false,
    this.fetchedOnce = false,
    this.error,
  });

  /// Oldest first, and **contiguous** — there is never a hole in the middle.
  /// That is the invariant paging depends on: [ChatController.loadOlder] pages
  /// before the first of these, so a gap anywhere above it could never be
  /// filled.
  final List<int> messageIds;

  /// A first page is on its way and there is nothing to show behind it.
  final bool loading;

  /// A page of history is on its way, under what is already on screen.
  final bool loadingOlder;

  final bool canLoadMorePast;

  /// Whether the site has answered at all, which is what tells an empty channel
  /// apart from one that has not been read yet.
  final bool fetchedOnce;

  final String? error;

  bool get isEmpty => fetchedOnce && error == null && messageIds.isEmpty;

  /// The message to page before. Null on an empty stream, where there is
  /// nothing to page from.
  int? get oldestId => messageIds.firstOrNull;

  ChatStreamState copyWith({
    List<int>? messageIds,
    bool? loading,
    bool? loadingOlder,
    bool? canLoadMorePast,
    bool? fetchedOnce,
    String? error,
    bool clearError = false,
  }) => ChatStreamState(
    messageIds: messageIds ?? this.messageIds,
    loading: loading ?? this.loading,
    loadingOlder: loadingOlder ?? this.loadingOlder,
    canLoadMorePast: canLoadMorePast ?? this.canLoadMorePast,
    fetchedOnce: fetchedOnce ?? this.fetchedOnce,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Which channels a site has, and which messages are in the one on screen.
///
/// Its own notifier rather than more state on `ShellController`, the way
/// `ReactionsController` and `UpdateController` are — though for a weaker
/// reason than theirs, and the difference is worth stating. A reactor list is
/// an *overlay*, orthogonal to whatever is on screen, so it must not redraw the
/// world. A channel list is navigation chrome and a message list is the main
/// region: the same class of state as the shell's own feeds and totals, both of
/// which already go through `ShellController._notify`. So this class is
/// separate for tidiness and testability, and the shell forwards its
/// notifications rather than proxying its state.
///
/// The escape hatch, for when step 2 puts live tracking on these rows at a few
/// messages a second: split the counts into a notifier of their own and stop
/// forwarding *that* one, leaving the sidebar rows to listen for themselves.
///
/// Only the *asking* and the *ordering* live here. The channels and the
/// messages go in the [Store] under their own ids, so the sidebar row and the
/// screen it opens are drawing one record rather than two copies.
class ChatController extends ChangeNotifier {
  ChatController({
    required this.api,
    required this.authenticator,
    required this.store,
  });

  final DiscourseApi api;
  final Authenticator authenticator;
  final Store store;

  /// How many messages to ask for. The site caps it at 50 and Discourse's own
  /// client sends exactly that.
  static const int pageSize = 50;

  /// How many times a site's channel list is worth asking for.
  ///
  /// Bounded like `_ensureCustomEmojis`: nothing on screen asks for this again,
  /// so a failure that could only be retried by an event which will not happen
  /// would be a dead end for the life of the session.
  static const int maxChannelAttempts = 3;

  /// Facts about requests rather than about records, which is why they are here
  /// and not in the [Store]: a channel that has never been fetched has nowhere
  /// to hold them.
  final Set<String> _loading = {};
  final Map<String, String> _errors = {};
  final Map<String, int> _attempts = {};

  /// Bumped per site on [forget], so a fetch in flight when a site was
  /// disconnected can tell on arrival that the store it fetched for has been
  /// emptied since, and put nothing back into it.
  final Map<String, int> _siteEpochs = {};

  int _siteEpoch(String siteUrl) => _siteEpochs[siteUrl] ?? 0;

  bool _disposed = false;

  /// Channel ids in the order the sidebar draws them. The channels themselves
  /// are in the [Store]; these two lists are the orderings, which no record
  /// holds.
  final Map<String, List<int>> _publicIds = {};
  final Map<String, List<int>> _directIds = {};

  /// One channel's stream, keyed `'$siteUrl~$channelId'`.
  final Map<String, ChatStreamState> _streams = {};

  static String _channelsKey(String siteUrl) => '$siteUrl~channels';
  static String _streamKey(String siteUrl, int id) => '$siteUrl~$id';
  static String _olderKey(String siteUrl, int id) => '$siteUrl~$id~past';

  // --- reads -------------------------------------------------------------

  /// The public channels this account follows, in sidebar order. Empty before
  /// the site has answered, which is also what a site with none looks like —
  /// deliberately, since nothing is drawn for either.
  List<ChatChannel> publicChannels(String siteUrl) =>
      _resolve(siteUrl, _publicIds[siteUrl]);

  List<ChatChannel> directChannels(String siteUrl) =>
      _resolve(siteUrl, _directIds[siteUrl]);

  List<ChatChannel> _resolve(String siteUrl, List<int>? ids) => [
    for (final id in ids ?? const <int>[]) ?store.read<ChatChannel>(siteUrl, id),
  ];

  ChatChannel? channel(String siteUrl, int channelId) =>
      store.read<ChatChannel>(siteUrl, channelId);

  /// A channel to watch rather than to read, so a row redraws itself when its
  /// record changes without anything above it rebuilding.
  Ref<ChatChannel> channelRef(String siteUrl, int channelId) =>
      store.ref<ChatChannel>(siteUrl, channelId);

  Ref<ChatMessage> messageRef(String siteUrl, int messageId) =>
      store.ref<ChatMessage>(siteUrl, messageId);

  ChatStreamState stream(String siteUrl, int channelId) =>
      _streams[_streamKey(siteUrl, channelId)] ?? const ChatStreamState();

  /// The messages of one channel, oldest first, as far as they are held.
  List<ChatMessage> messages(String siteUrl, int channelId) => [
    for (final id in stream(siteUrl, channelId).messageIds)
      ?store.read<ChatMessage>(siteUrl, id),
  ];

  String? channelsError(String siteUrl) => _errors[_channelsKey(siteUrl)];

  // --- writes ------------------------------------------------------------

  /// Fetches the channels this account follows on [siteUrl].
  ///
  /// Once per site rather than on every open, unlike the reactor lists: this
  /// decides what is in the sidebar, and a sidebar that re-fetched whenever a
  /// widget rebuilt would flicker. Keeping it fresh afterwards is what step 2's
  /// live tracking is for.
  ///
  /// Failure is silent and bounded. There is nothing on screen to put an error
  /// on — no chat section exists yet to hold one — and a site that will not
  /// answer is simply a site drawn without chat, which is the same argument
  /// `SiteConfig` makes for having no error state.
  Future<void> loadChannels(String siteUrl, {bool force = false}) async {
    final key = _channelsKey(siteUrl);
    if (!force && _publicIds.containsKey(siteUrl)) return;
    if ((_attempts[key] ?? 0) >= maxChannelAttempts) return;
    if (!_loading.add(key)) return;

    final epoch = _siteEpoch(siteUrl);
    _attempts[key] = (_attempts[key] ?? 0) + 1;

    try {
      // Inside the guard, not before it: an unsigned macOS build's keychain can
      // throw rather than answer, and reading it outside would leave this key
      // stranded in `_loading` for the life of the app.
      final channels = await api.chatChannels(
        siteUrl: siteUrl,
        apiKey: await authenticator.apiKeyFor(siteUrl),
        clientId: await authenticator.clientId(),
      );
      if (_disposed || epoch != _siteEpoch(siteUrl)) return;

      store.putAll(siteUrl, channels.public);
      store.putAll(siteUrl, channels.direct);
      _publicIds[siteUrl] = [for (final c in channels.public) c.id];
      _directIds[siteUrl] = [for (final c in channels.direct) c.id];
      _errors.remove(key);
      // A site that answered once has proved it can, so a later failure gets
      // its attempts back rather than inheriting the ones spent getting here.
      _attempts.remove(key);
    } catch (_) {
      if (_disposed || epoch != _siteEpoch(siteUrl)) return;
      _errors[key] = 'Could not load this site’s chat channels.';
    } finally {
      _loading.remove(key);
      _notify();
    }
  }

  /// Puts a channel's newest page on screen.
  ///
  /// Asked again on every open, the way the reactor lists are: this is a list of
  /// what other people have just said, it is stale within minutes, and there is
  /// nothing live yet to correct it. Whatever was fetched last time stays on
  /// screen while the answer is on its way.
  ///
  /// The answer **replaces** the stream rather than merging into it. Contiguity
  /// is what [loadOlder] depends on, and merging a newest page into an older one
  /// the reader had scrolled back to would leave a hole in the middle that
  /// nothing could ever fill.
  Future<void> openChannel(String siteUrl, int channelId) async {
    final key = _streamKey(siteUrl, channelId);
    if (!_loading.add(key)) return;

    final epoch = _siteEpoch(siteUrl);
    final held = stream(siteUrl, channelId);
    _streams[key] = held.copyWith(
      // Only a stream with nothing in it gets to show a spinner in place of
      // content; a re-open refreshes underneath what is already there.
      loading: held.messageIds.isEmpty,
      clearError: true,
    );
    _notify();

    try {
      final page = await api.chatMessages(
        siteUrl: siteUrl,
        channelId: channelId,
        pageSize: pageSize,
        apiKey: await authenticator.apiKeyFor(siteUrl),
        clientId: await authenticator.clientId(),
      );
      if (_disposed || epoch != _siteEpoch(siteUrl)) return;

      store.putAll(siteUrl, page.messages);
      _streams[key] = ChatStreamState(
        messageIds: _sortedIds(siteUrl, page.messages),
        canLoadMorePast: page.canLoadMorePast,
        fetchedOnce: true,
      );
    } catch (_) {
      if (_disposed || epoch != _siteEpoch(siteUrl)) return;
      // Messages already on screen are better than an error where they were:
      // they were true a moment ago, and the next open asks again.
      final current = _streams[key] ?? const ChatStreamState();
      _streams[key] = current.copyWith(
        fetchedOnce: true,
        error: current.messageIds.isEmpty
            ? 'Could not load this channel.'
            : null,
      );
    } finally {
      final current = _streams[key];
      if (current != null) _streams[key] = current.copyWith(loading: false);
      _loading.remove(key);
      _notify();
    }
  }

  /// Prepends the page immediately before the oldest message held.
  ///
  /// Does nothing when the site has said there is no more, when a page is
  /// already on its way, or before there is an oldest message to page from —
  /// each of which the view can and does ask for anyway, because the cheapest
  /// place to answer "no" is here.
  Future<void> loadOlder(String siteUrl, int channelId) async {
    final key = _streamKey(siteUrl, channelId);
    final held = stream(siteUrl, channelId);
    final before = held.oldestId;
    if (!held.canLoadMorePast || before == null) return;

    final guard = _olderKey(siteUrl, channelId);
    if (_loading.contains(key) || !_loading.add(guard)) return;

    final epoch = _siteEpoch(siteUrl);
    _streams[key] = held.copyWith(loadingOlder: true);
    _notify();

    try {
      final page = await api.chatMessages(
        siteUrl: siteUrl,
        channelId: channelId,
        before: before,
        pageSize: pageSize,
        apiKey: await authenticator.apiKeyFor(siteUrl),
        clientId: await authenticator.clientId(),
      );
      if (_disposed || epoch != _siteEpoch(siteUrl)) return;

      store.putAll(siteUrl, page.messages);
      // Re-read rather than closing over what was held before the request: a
      // re-open may have replaced the stream while this was away, and writing
      // back the captured copy would undo it.
      final current = _streams[key] ?? const ChatStreamState();
      final merged = _sortedIds(siteUrl, page.messages, held: current.messageIds);

      _streams[key] = current.copyWith(
        messageIds: merged,
        // "The page brought nothing new" overrides whatever the site said.
        // Without it a cursor the site keeps answering the same page for spins
        // the fill-pane fallback forever. Safe because the stream is contiguous
        // — every id a past page returns is strictly below the oldest held one,
        // so it is new by construction. Revisit if step 2 adds jump-to-message,
        // which can leave a gap a page legitimately lands inside.
        canLoadMorePast:
            merged.length > current.messageIds.length && page.canLoadMorePast,
        fetchedOnce: true,
      );
    } catch (_) {
      if (_disposed || epoch != _siteEpoch(siteUrl)) return;
      // History that would not load is not worth an error state: what is on
      // screen is still true, and scrolling up again asks again.
    } finally {
      final current = _streams[key];
      if (current != null) _streams[key] = current.copyWith(loadingOlder: false);
      _loading.remove(guard);
      _notify();
    }
  }

  /// Forgets a disconnected site.
  ///
  /// More than `ReactionsController.forget` drops, because more than the
  /// questions belong to this class: the two channel lists and every stream are
  /// orderings, and no record holds those. The channels and the messages
  /// themselves are the [Store]'s to forget.
  void forget(String siteUrl) {
    _loading.removeWhere((key) => key.startsWith('$siteUrl~'));
    _errors.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _attempts.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _streams.removeWhere((key, _) => key.startsWith('$siteUrl~'));
    _publicIds.remove(siteUrl);
    _directIds.remove(siteUrl);
    _siteEpochs[siteUrl] = _siteEpoch(siteUrl) + 1;
  }

  /// Union by id, ordered by `(createdAt, id)`.
  ///
  /// Deduping by id and not by identity, because the same message arrives twice
  /// whenever a page overlaps a boundary; the store has already merged the two
  /// copies into one record, and the list must not name it twice or the row is
  /// built twice.
  ///
  /// The tiebreak is load-bearing rather than tidy. `created_at` is serialised
  /// as iso8601, so two messages written in the same second carry equal dates
  /// on the wire; Dart's sort is unstable, so a date-only comparator lets those
  /// two swap places every time a page is merged and the list visibly
  /// reshuffles under the reader. The merge also has to be idempotent — folding
  /// a page that overlaps one already held must give the identical list — and a
  /// comparator that can return zero cannot promise that. `(created_at, id)` is
  /// the site's own `ORDER BY`.
  List<int> _sortedIds(
    String siteUrl,
    Iterable<ChatMessage> arrived, {
    List<int> held = const [],
  }) {
    final dates = <int, DateTime>{
      for (final id in held)
        if (store.read<ChatMessage>(siteUrl, id) case final message?)
          id: message.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      for (final message in arrived)
        message.id:
            message.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    };

    return dates.keys.toList()..sort((a, b) {
      final byDate = dates[a]!.compareTo(dates[b]!);
      return byDate != 0 ? byDate : a.compareTo(b);
    });
  }

  /// Unlike `ReactionsController`, this one *is* reached from a scroll handler:
  /// [loadOlder] is called from a scroll notification and from an `itemBuilder`.
  /// A viewport correcting an overshoot starts a scroll from inside its own
  /// `performLayout`, so a notification raised on that path would mark the tree
  /// dirty mid-frame, which is an error rather than a rebuild. Same deferral
  /// `ShellController._notify` makes, and for the same reason.
  bool _notifyScheduled = false;

  void _notify() {
    if (_disposed) return;

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_notifyScheduled) return;
      _notifyScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notifyScheduled = false;
        if (!_disposed) notifyListeners();
      });
      return;
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
