import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/bookmark_reminder_store.dart';
import '../foundation/clock_time.dart';
import '../foundation/timezone_environment.dart';
import '../models/bookmark.dart';
import '../models/bookmark_reminder.dart';
import '../models/post.dart';
import '../plugin_api/bookmark_host.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/d_icons.dart';
import 'adaptive_dialog_action.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';

final class _QuickMenuResult {
  const _QuickMenuResult.edit(this.bookmark);

  final Bookmark bookmark;
}

abstract interface class _BookmarkUiHost {
  BookmarkSession get session;

  Future<BookmarkWriteResult> createBookmark({
    required String siteUrl,
    required int targetId,
  });

  Future<BookmarkWriteResult> updateBookmark({
    required String siteUrl,
    required Bookmark bookmark,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
  });

  Future<BookmarkWriteResult> clearBookmarkReminder({
    required String siteUrl,
    required Bookmark bookmark,
  });

  Future<BookmarkWriteResult> deleteBookmark({
    required String siteUrl,
    required Bookmark bookmark,
  });
}

final class _CoreBookmarkUiHost implements _BookmarkUiHost {
  const _CoreBookmarkUiHost(this._host, this._topicId, this.session);

  final BookmarkTargetHost _host;
  final int _topicId;

  @override
  final BookmarkSession session;

  @override
  Future<BookmarkWriteResult> createBookmark({
    required String siteUrl,
    required int targetId,
  }) => _host.createBookmark(
    siteUrl: siteUrl,
    topicId: _topicId,
    targetId: targetId,
  );

  @override
  Future<BookmarkWriteResult> updateBookmark({
    required String siteUrl,
    required Bookmark bookmark,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
  }) => _host.updateBookmark(
    siteUrl: siteUrl,
    topicId: _topicId,
    bookmark: bookmark,
    name: name,
    reminderAt: reminderAt,
    autoDeletePreference: autoDeletePreference,
  );

  @override
  Future<BookmarkWriteResult> clearBookmarkReminder({
    required String siteUrl,
    required Bookmark bookmark,
  }) => _host.clearBookmarkReminder(
    siteUrl: siteUrl,
    topicId: _topicId,
    bookmark: bookmark,
  );

  @override
  Future<BookmarkWriteResult> deleteBookmark({
    required String siteUrl,
    required Bookmark bookmark,
  }) => _host.deleteBookmark(
    siteUrl: siteUrl,
    topicId: _topicId,
    bookmark: bookmark,
  );
}

final class _PluginBookmarkUiHost implements _BookmarkUiHost {
  const _PluginBookmarkUiHost(this._host, this.session);

  final PluginBookmarkHost _host;

  @override
  final BookmarkSession session;

  @override
  Future<BookmarkWriteResult> createBookmark({
    required String siteUrl,
    required int targetId,
  }) => _host.createBookmark(siteUrl: siteUrl, targetId: targetId);

  @override
  Future<BookmarkWriteResult> updateBookmark({
    required String siteUrl,
    required Bookmark bookmark,
    String? name,
    DateTime? reminderAt,
    required BookmarkAutoDeletePreference autoDeletePreference,
  }) => _host.updateBookmark(
    siteUrl: siteUrl,
    bookmark: bookmark,
    name: name,
    reminderAt: reminderAt,
    autoDeletePreference: autoDeletePreference,
  );

  @override
  Future<BookmarkWriteResult> clearBookmarkReminder({
    required String siteUrl,
    required Bookmark bookmark,
  }) => _host.clearBookmarkReminder(siteUrl: siteUrl, bookmark: bookmark);

  @override
  Future<BookmarkWriteResult> deleteBookmark({
    required String siteUrl,
    required Bookmark bookmark,
  }) => _host.deleteBookmark(siteUrl: siteUrl, bookmark: bookmark);
}

Future<void> showPostBookmarkMenu({
  required BuildContext context,
  required BookmarkHost controller,
  required String siteUrl,
  required int topicId,
  required Post post,
}) async {
  final actions = controller.bookmarkTarget(BookmarkTargetType.post);
  final session = actions.captureSession(siteUrl);
  final uiActions = _CoreBookmarkUiHost(actions, topicId, session);
  final result = await showShellSheet<_QuickMenuResult>(
    context: context,
    title: post.bookmark == null ? appL10n.bookmarkPost : appL10n.postBookmark,
    dialogOnDesktop: true,
    builder: (_) => _BookmarkQuickSheet(
      controller: uiActions,
      siteUrl: siteUrl,
      targetId: post.id,
      initialBookmark: post.bookmark,
    ),
  );
  if (result == null || !context.mounted || !_canAct(context, session)) return;
  await _showBookmarkEditor(
    context: context,
    controller: uiActions,
    siteUrl: siteUrl,
    bookmark: result.bookmark,
    cooked: post.cooked,
  );
}

Future<void> showPluginBookmarkMenu({
  required BuildContext context,
  required PluginBookmarkHost controller,
  required String siteUrl,
  required int targetId,
  required Bookmark? bookmark,
  required String cooked,
  required String createTitle,
  required String existingTitle,
}) async {
  final session = controller.captureSession(siteUrl);
  final uiActions = _PluginBookmarkUiHost(controller, session);
  final result = await showShellSheet<_QuickMenuResult>(
    context: context,
    title: bookmark == null ? createTitle : existingTitle,
    dialogOnDesktop: true,
    builder: (_) => _BookmarkQuickSheet(
      controller: uiActions,
      siteUrl: siteUrl,
      targetId: targetId,
      initialBookmark: bookmark,
    ),
  );
  if (result == null || !context.mounted || !_canAct(context, session)) return;
  await _showBookmarkEditor(
    context: context,
    controller: uiActions,
    siteUrl: siteUrl,
    bookmark: result.bookmark,
    cooked: cooked,
  );
}

Future<void> showTopicBookmarkMenu({
  required BuildContext context,
  required BookmarkHost controller,
  required String siteUrl,
  required TopicDetail topic,
}) async {
  final topicActions = controller.bookmarkTarget(BookmarkTargetType.topic);
  final postActions = controller.bookmarkTarget(BookmarkTargetType.post);
  final session = topicActions.captureSession(siteUrl);
  final topicUiActions = _CoreBookmarkUiHost(topicActions, topic.id, session);
  final postUiActions = _CoreBookmarkUiHost(postActions, topic.id, session);
  if (topic.postBookmarks.isEmpty) {
    final result = await showShellSheet<_QuickMenuResult>(
      context: context,
      title: topic.topicBookmark == null
          ? appL10n.bookmarkTopic
          : appL10n.topicBookmark,
      dialogOnDesktop: true,
      builder: (_) => _BookmarkQuickSheet(
        controller: topicUiActions,
        siteUrl: siteUrl,
        targetId: topic.id,
        initialBookmark: topic.topicBookmark,
      ),
    );
    if (result == null || !context.mounted || !_canAct(context, session)) {
      return;
    }
    await _showBookmarkEditor(
      context: context,
      controller: topicUiActions,
      siteUrl: siteUrl,
      bookmark: result.bookmark,
    );
    return;
  }

  final result = await showShellSheet<_TopicBookmarksAction>(
    context: context,
    title: appL10n.topicBookmarks,
    dialogOnDesktop: true,
    builder: (_) => _TopicBookmarksSheet(
      session: session,
      siteUrl: siteUrl,
      topicId: topic.id,
    ),
  );
  if (result == null || !context.mounted || !_canAct(context, session)) return;
  switch (result.kind) {
    case _TopicBookmarksActionKind.jump:
      controller.openTopicPost(
        siteUrl: siteUrl,
        topicId: topic.id,
        postNumber: result.postNumber!,
      );
    case _TopicBookmarksActionKind.topic:
      final current =
          controller.store.read<TopicDetail>(siteUrl, topic.id) ?? topic;
      final quick = await showShellSheet<_QuickMenuResult>(
        context: context,
        title: current.topicBookmark == null
            ? appL10n.bookmarkTopic
            : appL10n.topicBookmark,
        dialogOnDesktop: true,
        builder: (_) => _BookmarkQuickSheet(
          controller: topicUiActions,
          siteUrl: siteUrl,
          targetId: topic.id,
          initialBookmark: current.topicBookmark,
        ),
      );
      if (quick != null && context.mounted && _canAct(context, session)) {
        await _showBookmarkEditor(
          context: context,
          controller: topicUiActions,
          siteUrl: siteUrl,
          bookmark: quick.bookmark,
        );
      }
    case _TopicBookmarksActionKind.edit:
      final bookmark = result.bookmark!;
      final targetType = bookmark.coreTargetType;
      if (targetType == null) return;
      final post = bookmark.bookmarkableId == null
          ? null
          : controller.store.read<Post>(siteUrl, bookmark.bookmarkableId!);
      await _showBookmarkEditor(
        context: context,
        controller: targetType == BookmarkTargetType.post
            ? postUiActions
            : topicUiActions,
        siteUrl: siteUrl,
        bookmark: bookmark,
        cooked: post?.cooked,
      );
    case _TopicBookmarksActionKind.delete:
      final bookmark = result.bookmark!;
      final targetType = bookmark.coreTargetType;
      if (targetType == null) return;
      if (bookmark.reminderAt != null &&
          !await _confirm(
            context,
            title: appL10n.deleteBookmark,
            message: appL10n.thisAlsoRemovesItsScheduledReminder,
            action: appL10n.delete,
          )) {
        return;
      }
      if (!context.mounted || !_canAct(context, session)) return;
      final write =
          await (targetType == BookmarkTargetType.post
                  ? postActions
                  : topicActions)
              .deleteBookmark(
                siteUrl: siteUrl,
                topicId: topic.id,
                bookmark: bookmark,
              );
      if (context.mounted && _canAct(context, session)) {
        _showWriteMessage(context, write);
      }
    case _TopicBookmarksActionKind.clearAll:
      if (!await _confirm(
        context,
        title: appL10n.deleteAllBookmarks,
        message: appL10n.everyTopicAndPostBookmarkInThisTopicWillBeRemoved,
        action: appL10n.deleteAll,
      )) {
        return;
      }
      if (!context.mounted || !_canAct(context, session)) return;
      final write = await controller.deleteAllTopicBookmarks(
        siteUrl: siteUrl,
        topicId: topic.id,
      );
      if (context.mounted && _canAct(context, session)) {
        _showWriteMessage(context, write);
      }
  }
}

Future<void> showBookmarkEditor({
  required BuildContext context,
  required BookmarkTargetHost controller,
  required String siteUrl,
  required int topicId,
  required Bookmark bookmark,
  String? cooked,
  DateTime Function()? now,
}) => _showBookmarkEditor(
  context: context,
  controller: _CoreBookmarkUiHost(
    controller,
    topicId,
    controller.captureSession(siteUrl),
  ),
  siteUrl: siteUrl,
  bookmark: bookmark,
  cooked: cooked,
  now: now,
);

Future<void> _showBookmarkEditor({
  required BuildContext context,
  required _BookmarkUiHost controller,
  required String siteUrl,
  required Bookmark bookmark,
  String? cooked,
  DateTime Function()? now,
}) => showShellSheet<void>(
  context: context,
  title: appL10n.editBookmark,
  dialogOnDesktop: true,
  builder: (_) => _BookmarkEditor(
    controller: controller,
    siteUrl: siteUrl,
    bookmark: bookmark,
    cooked: cooked,
    now: now ?? DateTime.now,
  ),
);

class _BookmarkQuickSheet extends StatefulWidget {
  const _BookmarkQuickSheet({
    required this.controller,
    required this.siteUrl,
    required this.targetId,
    required this.initialBookmark,
  });

  final _BookmarkUiHost controller;
  final String siteUrl;
  final int targetId;
  final Bookmark? initialBookmark;

  @override
  State<_BookmarkQuickSheet> createState() => _BookmarkQuickSheetState();
}

class _BookmarkQuickSheetState extends State<_BookmarkQuickSheet> {
  bool get _canUseSession =>
      mounted && _canAct(context, widget.controller.session);

  Bookmark? _bookmark;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _bookmark = widget.initialBookmark;
    if (_bookmark == null) unawaited(_create());
  }

  Future<void> _create() async {
    if (!widget.controller.session.isCurrent) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.controller.createBookmark(
      siteUrl: widget.siteUrl,
      targetId: widget.targetId,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!_canUseSession) return;
    setState(() {
      _bookmark = result.bookmark;
      _error = result.message;
    });
  }

  Future<void> _setReminder(DateTime reminder) async {
    if (!_canUseSession) return;
    final bookmark = _bookmark;
    if (bookmark == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.controller.updateBookmark(
      siteUrl: widget.siteUrl,
      bookmark: bookmark,
      name: bookmark.name,
      reminderAt: reminder,
      autoDeletePreference: bookmark.autoDeletePreference,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!_canUseSession) return;
    if (result.saved) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _error = result.message;
    });
  }

  Future<void> _clearReminder() async {
    if (!_canUseSession) return;
    final bookmark = _bookmark;
    if (bookmark == null) return;
    setState(() => _busy = true);
    final result = await widget.controller.clearBookmarkReminder(
      siteUrl: widget.siteUrl,
      bookmark: bookmark,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!_canUseSession) return;
    if (result.saved) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _error = result.message;
    });
  }

  Future<void> _delete() async {
    if (!_canUseSession) return;
    final bookmark = _bookmark;
    if (bookmark == null) return;
    if (bookmark.reminderAt != null &&
        !await _confirm(
          context,
          title: appL10n.deleteBookmark,
          message: appL10n.thisAlsoRemovesItsScheduledReminder,
          action: appL10n.delete,
        )) {
      return;
    }
    if (!_canUseSession) return;
    setState(() => _busy = true);
    final result = await widget.controller.deleteBookmark(
      siteUrl: widget.siteUrl,
      bookmark: bookmark,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!_canUseSession) return;
    if (result.saved) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _error = result.message;
    });
  }

  void _edit(Bookmark bookmark) {
    if (!_canUseSession) return;
    Navigator.of(context).pop(_QuickMenuResult.edit(bookmark));
  }

  @override
  Widget build(BuildContext context) {
    final siteContext = widget.controller.session.siteContext;
    final environment = TimezoneEnvironment.instance;
    final zoneName = environment.readerTimezone(siteContext.timezone);
    final location = environment.location(zoneName)!;
    final suggestions = BookmarkReminderCalculator.quickSuggestions(
      now: DateTime.now(),
      location: location,
    );
    final bookmark = _bookmark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_busy) ...[
          DProgress(semanticsLabel: context.l10n.savingBookmark),
          const SizedBox(height: 16),
        ],
        if (_error case final error?) ...[
          Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 12),
        ],
        if (bookmark == null)
          Text(
            _busy
                ? context.l10n.savingBookmarkBookmarkui
                : context.l10n.theBookmarkWasNotSaved,
          )
        else if (widget.initialBookmark == null) ...[
          Text(
            context.l10n.bookmarkedBookmarkui,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          for (final suggestion in suggestions)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const DIcon(DIcons.farClock),
              title: Text(suggestion.label),
              subtitle: Text(
                _formatReminder(context, suggestion.instant, zoneName),
              ),
              enabled: !_busy,
              onTap: _busy ? null : () => _setReminder(suggestion.instant),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const DIcon(DIcons.pencil),
            title: Text(context.l10n.moreOptions),
            enabled: !_busy,
            onTap: _busy ? null : () => _edit(bookmark),
          ),
        ] else ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const DIcon(DIcons.pencil),
            title: Text(context.l10n.editBookmark),
            enabled: !_busy,
            onTap: _busy ? null : () => _edit(bookmark),
          ),
          if (bookmark.reminderAt != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const DIcon(DIcons.farClock),
              title: Text(context.l10n.clearReminder),
              enabled: !_busy,
              onTap: _busy ? null : _clearReminder,
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: DIcon(
              DIcons.trashCan,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              context.l10n.deleteBookmarkBookmarkui,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            enabled: !_busy,
            onTap: _busy ? null : _delete,
          ),
        ],
      ],
    );
  }
}

class _BookmarkEditor extends StatefulWidget {
  const _BookmarkEditor({
    required this.controller,
    required this.siteUrl,
    required this.bookmark,
    required this.now,
    this.cooked,
  });

  final _BookmarkUiHost controller;
  final String siteUrl;
  final Bookmark bookmark;
  final DateTime Function() now;
  final String? cooked;

  @override
  State<_BookmarkEditor> createState() => _BookmarkEditorState();
}

class _BookmarkEditorState extends State<_BookmarkEditor> {
  bool get _canUseSession =>
      mounted && _canAct(context, widget.controller.session);

  String? get _nameError => _name.text.trim().runes.length > 100
      ? appL10n.bookmarkNotesMustBe100CharactersOrFewer
      : null;

  late final TextEditingController _name;
  final TextEditingController _relative = TextEditingController(text: '1');
  late BookmarkAutoDeletePreference _preference;
  DateTime? _reminder;
  DateTime? _lastCustom;
  DateTime? _postDate;
  String? _error;
  bool _busy = false;
  bool _suggestionsLoaded = false;
  _RelativeUnit _relativeUnit = _RelativeUnit.days;
  final BookmarkReminderStore _store = const BookmarkReminderStore();

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.bookmark.name ?? '');
    _preference = widget.bookmark.autoDeletePreference;
    _reminder = widget.bookmark.reminderAt;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_suggestionsLoaded) return;
    _suggestionsLoaded = true;
    unawaited(_loadSuggestions());
  }

  Future<void> _loadSuggestions() async {
    if (!widget.controller.session.isCurrent) return;
    final registry = PluginScope.of(context).registry;
    final siteContext = widget.controller.session.siteContext;
    final username = siteContext.username;
    final last = username == null
        ? null
        : await _store.read(widget.siteUrl, username);
    final postDate = widget.cooked == null
        ? null
        : registry.futureBookmarkReminder(
            widget.cooked!,
            accountTimezone: siteContext.timezone,
          );
    if (!_canUseSession) return;
    setState(() {
      _lastCustom = last?.isAfter(widget.now()) == true ? last : null;
      _postDate = postDate;
    });
  }

  Future<void> _pickCustom() async {
    if (!_canUseSession) return;
    final environment = TimezoneEnvironment.instance;
    final siteContext = widget.controller.session.siteContext;
    final zoneName = environment.readerTimezone(siteContext.timezone);
    final location = environment.location(zoneName)!;
    final now = widget.now();
    final wallNow = tzDate(now, location);
    final wallInitial = tzDate(
      _reminder ?? now.add(const Duration(hours: 1)),
      location,
    );
    // Picker dates represent account-local calendar days, not instants.
    final firstDate = DateTime(wallNow.year, wallNow.month, wallNow.day);
    final lastDate = DateTime(wallNow.year + 10, wallNow.month, wallNow.day);
    var initialDate = DateTime(
      wallInitial.year,
      wallInitial.month,
      wallInitial.day,
    );
    if (initialDate.isBefore(firstDate)) initialDate = firstDate;
    if (initialDate.isAfter(lastDate)) initialDate = lastDate;
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      currentDate: firstDate,
    );
    if (date == null || !mounted || !_canUseSession) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: wallInitial.hour,
        minute: wallInitial.minute,
      ),
    );
    if (time == null || !mounted || !_canUseSession) return;
    final instant = BookmarkReminderCalculator.resolveWallTime(
      location: location,
      date: date,
      hour: time.hour,
      minute: time.minute,
    );
    if (instant == null) {
      setState(
        () => _error =
            appL10n.thatLocalTimeDoesNotExistBecauseOfDaylightSavingTime,
      );
      return;
    }
    setState(() {
      _reminder = instant;
      _lastCustom = instant;
      _error = null;
    });
    if (siteContext.username case final username?) {
      unawaited(_store.write(widget.siteUrl, username, instant));
    }
  }

  void _setRelative() {
    final amount = int.tryParse(_relative.text.trim());
    if (amount == null || amount < 1 || amount > 3650) {
      setState(() => _error = appL10n.enterAPositiveReminderDuration);
      return;
    }
    setState(() {
      _reminder = widget.now().add(_relativeUnit.duration(amount)).toUtc();
      _error = null;
    });
  }

  Future<void> _save() async {
    if (!_canUseSession || _busy || _nameError != null) return;
    final now = widget.now().toUtc();
    final reminder = _reminder?.toUtc();
    if (reminder != null && !reminder.isAfter(now)) {
      setState(() => _error = appL10n.chooseAReminderInTheFuture);
      return;
    }
    final maximum = DateTime.utc(
      now.year + 10,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
      now.millisecond,
      now.microsecond,
    );
    if (reminder != null && reminder.isAfter(maximum)) {
      setState(() => _error = appL10n.chooseAReminderNoMoreThan10YearsAway);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final text = _name.text.trim();
    final result = await widget.controller.updateBookmark(
      siteUrl: widget.siteUrl,
      bookmark: widget.bookmark,
      name: text.isEmpty ? null : text,
      reminderAt: reminder,
      autoDeletePreference: _preference,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!_canUseSession) return;
    if (result.saved) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _error = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final siteContext = widget.controller.session.siteContext;
    final environment = TimezoneEnvironment.instance;
    final zoneName = environment.readerTimezone(siteContext.timezone);
    final location = environment.location(zoneName)!;
    final presets = BookmarkReminderCalculator.fullSuggestions(
      now: widget.now(),
      location: location,
      suggestWeekends: siteContext.suggestWeekendsInDatePickers,
    );

    return Form(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DInput(
            style: Theme.of(context).textTheme.bodyMedium,
            controller: _name,
            maxLength: 100,
            enabled: !_busy,
            labelText: context.l10n.noteBookmarkui,
            hintText: context.l10n.whyAreYouSavingThis,
            errorText: _nameError,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          DSelect<BookmarkAutoDeletePreference>.controlled(
            isExpanded: true,
            value: _preference,
            label: Text(context.l10n.afterward),
            entries: [
              for (final preference in BookmarkAutoDeletePreference.values)
                DSelectOption(
                  value: preference,
                  label: _preferenceLabel(preference),
                  child: Text(_preferenceLabel(preference)),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _preference = value!),
            initialValue: _preference,
            enabled: !_busy,
          ),
          const SizedBox(height: 20),
          Text(
            context.l10n.remindMe,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.timesUse((zoneName).toString()),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in presets)
                ActionChip(
                  label: Text(preset.label),
                  onPressed: _busy
                      ? null
                      : () => setState(() => _reminder = preset.instant),
                ),
              if (_postDate case final postDate?)
                ActionChip(
                  avatar: const DIcon(DIcons.farClock, size: 16),
                  label: Text(context.l10n.dateInPost),
                  onPressed: _busy
                      ? null
                      : () => setState(() => _reminder = postDate),
                ),
              if (_lastCustom case final last?)
                ActionChip(
                  label: Text(context.l10n.lastCustomTime),
                  onPressed: _busy
                      ? null
                      : () => setState(() => _reminder = last),
                ),
              ActionChip(
                label: Text(context.l10n.customDateAndTime),
                onPressed: _busy ? null : _pickCustom,
              ),
              ActionChip(
                label: Text(context.l10n.noReminder),
                onPressed: _busy
                    ? null
                    : () => setState(() => _reminder = null),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 84,
                child: TextField(
                  style: Theme.of(context).textTheme.bodyMedium,
                  controller: _relative,
                  keyboardType: TextInputType.number,
                  enabled: !_busy,
                  decoration: InputDecoration(
                    labelText: context.l10n.messageIn,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DSelect<_RelativeUnit>.controlled(
                  isExpanded: true,
                  value: _relativeUnit,
                  entries: [
                    for (final unit in _RelativeUnit.values)
                      DSelectOption(
                        value: unit,
                        label: unit.label,
                        child: Text(unit.label),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _relativeUnit = value!),
                  initialValue: _relativeUnit,
                  enabled: !_busy,
                ),
              ),
              const SizedBox(width: DSpacing.controlGap),
              DButton(
                label: Text(context.l10n.messageSet),
                onPressed: _busy ? null : _setRelative,
              ),
            ],
          ),
          if (_reminder case final reminder?) ...[
            const SizedBox(height: 12),
            Text(
              context.l10n.reminder(
                (_formatReminder(context, reminder, zoneName)).toString(),
              ),
            ),
          ],
          if (_error case final error?) ...[
            const SizedBox(height: 12),
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              DButton(
                label: Text(context.l10n.cancel),
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: DSpacing.controlGap),
              DButton(
                label: Text(context.l10n.save),
                onPressed: _nameError == null ? _save : null,
                variant: DButtonVariant.primary,
                loading: _busy,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _name.dispose();
    _relative.dispose();
    super.dispose();
  }
}

enum _RelativeUnit {
  hours('hours'),
  days('days'),
  weeks('weeks');

  const _RelativeUnit(this.label);
  final String label;

  Duration duration(int amount) => switch (this) {
    hours => Duration(hours: amount),
    days => Duration(days: amount),
    weeks => Duration(days: amount * 7),
  };
}

enum _TopicBookmarksActionKind { jump, topic, edit, delete, clearAll }

final class _TopicBookmarksAction {
  const _TopicBookmarksAction(this.kind, {this.bookmark, this.postNumber});
  final _TopicBookmarksActionKind kind;
  final Bookmark? bookmark;
  final int? postNumber;
}

class _TopicBookmarksSheet extends StatelessWidget {
  const _TopicBookmarksSheet({
    required this.session,
    required this.siteUrl,
    required this.topicId,
  });

  final BookmarkSession session;
  final String siteUrl;
  final int topicId;

  void _choose(BuildContext context, _TopicBookmarksAction action) {
    if (!context.mounted || !_canAct(context, session)) return;
    Navigator.of(context).pop(action);
  }

  @override
  Widget build(
    BuildContext context,
  ) => ShellSelector<({TopicDetail? topic, String busyTargets})>(
    select: (shell) {
      if (!session.isCurrent) return (topic: null, busyTargets: '');
      final topic = shell.store.read<TopicDetail>(siteUrl, topicId);
      final busy = <String>[];
      if (topic != null) {
        if (shell.bookmarkWriteInFlight(
          siteUrl: siteUrl,
          topicId: topicId,
          targetType: BookmarkTargetType.topic,
          targetId: topicId,
        )) {
          busy.add('topic');
        }
        for (final bookmark in topic.postBookmarks) {
          final targetId = bookmark.bookmarkableId;
          if (targetId != null &&
              shell.bookmarkWriteInFlight(
                siteUrl: siteUrl,
                topicId: topicId,
                targetType: BookmarkTargetType.post,
                targetId: targetId,
              )) {
            busy.add('$targetId');
          }
        }
      }
      return (topic: topic, busyTargets: busy.join(','));
    },
    builder: (context, snapshot, _) {
      final topic = snapshot.topic;
      if (topic == null) {
        return Text(context.l10n.thisTopicIsNoLongerAvailable);
      }
      final siteContext = session.siteContext;
      final zoneName = TimezoneEnvironment.instance.readerTimezone(
        siteContext.timezone,
      );
      final topicBusy = snapshot.busyTargets.split(',').contains('topic');
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: DIcon(
              topic.topicBookmark == null
                  ? DIcons.farBookmark
                  : topic.topicBookmark!.reminderAt == null
                  ? DIcons.bookmark
                  : DIcons.discourseBookmarkClock,
            ),
            title: Text(
              topic.topicBookmark == null
                  ? context.l10n.bookmarkTopic
                  : context.l10n.topicBookmark,
            ),
            subtitle: _bookmarkContext(context, topic.topicBookmark, zoneName),
            enabled: !topicBusy,
            onTap: topicBusy
                ? null
                : () => _choose(
                    context,
                    const _TopicBookmarksAction(
                      _TopicBookmarksActionKind.topic,
                    ),
                  ),
          ),
          const DSeparator(),
          for (final bookmark in topic.postBookmarks)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: DIcon(
                bookmark.reminderAt == null
                    ? DIcons.bookmark
                    : DIcons.discourseBookmarkClock,
              ),
              title: Text(
                context.l10n.postBookmarkui(
                  (bookmark.postNumber ?? '?').toString(),
                ),
              ),
              subtitle: _bookmarkContext(context, bookmark, zoneName),
              enabled: !snapshot.busyTargets
                  .split(',')
                  .contains('${bookmark.bookmarkableId}'),
              onTap:
                  bookmark.postNumber == null ||
                      snapshot.busyTargets
                          .split(',')
                          .contains('${bookmark.bookmarkableId}')
                  ? null
                  : () => _choose(
                      context,
                      _TopicBookmarksAction(
                        _TopicBookmarksActionKind.jump,
                        postNumber: bookmark.postNumber,
                      ),
                    ),
              trailing: Builder(
                builder: (menuContext) {
                  void onSelect(_TopicBookmarksActionKind kind) => _choose(
                    context,
                    _TopicBookmarksAction(
                      kind,
                      bookmark: bookmark,
                      postNumber: kind == _TopicBookmarksActionKind.jump
                          ? bookmark.postNumber
                          : null,
                    ),
                  );
                  return Semantics(
                    container: true,
                    explicitChildNodes: true,
                    child: DDropdownMenu(
                      content: DDropdownMenuContent(
                        semanticLabel: context.l10n.postBookmarkActions,
                        width: 280,
                        children: [
                          if (bookmark.postNumber != null)
                            DDropdownMenuItem(
                              onPressed: () =>
                                  onSelect(_TopicBookmarksActionKind.jump),
                              child: Text(context.l10n.jump),
                            ),
                          DDropdownMenuItem(
                            onPressed: () =>
                                onSelect(_TopicBookmarksActionKind.edit),
                            child: Text(context.l10n.edit),
                          ),
                          DDropdownMenuItem(
                            onPressed: () =>
                                onSelect(_TopicBookmarksActionKind.delete),
                            variant: DDropdownMenuItemVariant.destructive,
                            child: Text(context.l10n.delete),
                          ),
                        ],
                      ),
                      child: DDropdownMenuTrigger(
                        builder: (triggerContext, state) => DButton.iconOnly(
                          tooltip: context.l10n.postBookmarkActions,
                          variant: DButtonVariant.ghost,
                          icon: const Icon(Icons.more_vert),
                          focusNode: state.focusNode,
                          hasPopup: true,
                          expanded: state.open,
                          onPressed:
                              !snapshot.busyTargets
                                  .split(',')
                                  .contains('${bookmark.bookmarkableId}')
                              ? state.toggle
                              : null,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          if (topic.bookmarks.length > 1) ...[
            const DSeparator(),
            DButton(
              label: Text(context.l10n.deleteAllBookmarksBookmarkui),
              onPressed: snapshot.busyTargets.isNotEmpty
                  ? null
                  : () => _choose(
                      context,
                      const _TopicBookmarksAction(
                        _TopicBookmarksActionKind.clearAll,
                      ),
                    ),
              icon: const DIcon(DIcons.trashCan),
              variant: DButtonVariant.destructive,
            ),
          ],
        ],
      );
    },
  );
}

Widget? _bookmarkContext(
  BuildContext context,
  Bookmark? bookmark,
  String zoneName,
) {
  if (bookmark == null) return null;
  final lines = <String>[
    if (bookmark.name case final name? when name.isNotEmpty) name,
    if (bookmark.reminderAt case final reminder?)
      context.l10n.reminder(
        (_formatReminder(context, reminder, zoneName)).toString(),
      ),
  ];
  if (lines.isEmpty) return null;
  return Text(lines.join('\n'), maxLines: 3, overflow: TextOverflow.ellipsis);
}

// Account ownership survives ordinary navigation within the shell, but a
// delayed dialog result must only act while its own route is on top.
bool _canAct(BuildContext context, BookmarkSession session) =>
    context.mounted &&
    session.isCurrent &&
    ModalRoute.of(context)?.isCurrent == true;

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async =>
    await showDiscourseAlertDialog<bool>(
      context: context,
      title: Text(title),
      description: Text(message),
      cancelLabel: Text(appL10n.cancel),
      actionLabel: Text(action),
      cancelResult: false,
      actionResult: true,
      actionVariant: DButtonVariant.destructive,
    ) ??
    false;

void _showWriteMessage(BuildContext context, BookmarkWriteResult result) {
  if (result.message case final message?) {
    DToast.show(context, message);
  }
}

String _preferenceLabel(BookmarkAutoDeletePreference preference) =>
    switch (preference) {
      BookmarkAutoDeletePreference.never => appL10n.keepBookmark,
      BookmarkAutoDeletePreference.whenReminderSent =>
        appL10n.deleteAfterTheReminder,
      BookmarkAutoDeletePreference.onOwnerReply => appL10n.deleteOnceIReply,
      BookmarkAutoDeletePreference.clearReminder =>
        appL10n.keepBookmarkAndClearReminder,
    };

String _formatReminder(
  BuildContext context,
  DateTime instant,
  String zoneName,
) {
  final environment = TimezoneEnvironment.instance;
  final wall = tzDate(instant, environment.location(zoneName)!);
  final localizations = MaterialLocalizations.of(context);
  return appL10n.at(
    (localizations.formatMediumDate(wall)).toString(),
    (clockTimeLabel(context, wall)).toString(),
  );
}

tz.TZDateTime tzDate(DateTime instant, tz.Location location) {
  // Kept at this seam so the UI never relies on the device-local DateTime zone.
  return tz.TZDateTime.from(instant, location);
}
