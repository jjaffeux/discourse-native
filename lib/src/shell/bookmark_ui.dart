import 'dart:async';

import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/bookmark_reminder_store.dart';
import '../foundation/timezone_environment.dart';
import '../models/bookmark.dart';
import '../models/bookmark_reminder.dart';
import '../models/post.dart';
import '../plugin_api/bookmark_host.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'adaptive_dialog_action.dart';
import 'shell_scope.dart';
import 'shell_sheet.dart';

final class _QuickMenuResult {
  const _QuickMenuResult.edit(this.bookmark);

  final Bookmark bookmark;
}

Future<void> showPostBookmarkMenu({
  required BuildContext context,
  required BookmarkHost controller,
  required String siteUrl,
  required int topicId,
  required Post post,
}) async {
  final actions = controller.bookmarkTarget(BookmarkTargetType.post);
  final result = await showShellSheet<_QuickMenuResult>(
    context: context,
    title: post.bookmark == null ? 'Bookmark post' : 'Post bookmark',
    dialogOnDesktop: true,
    builder: (_) => _BookmarkQuickSheet(
      controller: actions,
      siteUrl: siteUrl,
      topicId: topicId,
      targetId: post.id,
      initialBookmark: post.bookmark,
    ),
  );
  if (result == null || !context.mounted) return;
  await showBookmarkEditor(
    context: context,
    controller: actions,
    siteUrl: siteUrl,
    topicId: topicId,
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
  final result = await showShellSheet<_QuickMenuResult>(
    context: context,
    title: bookmark == null ? createTitle : existingTitle,
    dialogOnDesktop: true,
    builder: (_) => _BookmarkQuickSheet(
      controller: controller,
      siteUrl: siteUrl,
      topicId: 0,
      targetId: targetId,
      initialBookmark: bookmark,
    ),
  );
  if (result == null || !context.mounted) return;
  await showBookmarkEditor(
    context: context,
    controller: controller,
    siteUrl: siteUrl,
    topicId: 0,
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
  if (topic.postBookmarks.isEmpty) {
    final result = await showShellSheet<_QuickMenuResult>(
      context: context,
      title: topic.topicBookmark == null ? 'Bookmark topic' : 'Topic bookmark',
      dialogOnDesktop: true,
      builder: (_) => _BookmarkQuickSheet(
        controller: topicActions,
        siteUrl: siteUrl,
        topicId: topic.id,
        targetId: topic.id,
        initialBookmark: topic.topicBookmark,
      ),
    );
    if (result == null || !context.mounted) return;
    await showBookmarkEditor(
      context: context,
      controller: topicActions,
      siteUrl: siteUrl,
      topicId: topic.id,
      bookmark: result.bookmark,
    );
    return;
  }

  final result = await showShellSheet<_TopicBookmarksAction>(
    context: context,
    title: 'Topic bookmarks',
    dialogOnDesktop: true,
    builder: (_) => _TopicBookmarksSheet(
      controller: controller,
      siteUrl: siteUrl,
      topicId: topic.id,
    ),
  );
  if (result == null || !context.mounted) return;
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
            ? 'Bookmark topic'
            : 'Topic bookmark',
        dialogOnDesktop: true,
        builder: (_) => _BookmarkQuickSheet(
          controller: topicActions,
          siteUrl: siteUrl,
          topicId: topic.id,
          targetId: topic.id,
          initialBookmark: current.topicBookmark,
        ),
      );
      if (quick != null && context.mounted) {
        await showBookmarkEditor(
          context: context,
          controller: topicActions,
          siteUrl: siteUrl,
          topicId: topic.id,
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
      await showBookmarkEditor(
        context: context,
        controller: targetType == BookmarkTargetType.post
            ? postActions
            : topicActions,
        siteUrl: siteUrl,
        topicId: topic.id,
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
            title: 'Delete bookmark?',
            message: 'This also removes its scheduled reminder.',
            action: 'Delete',
          )) {
        return;
      }
      final write =
          await (targetType == BookmarkTargetType.post
                  ? postActions
                  : topicActions)
              .deleteBookmark(
                siteUrl: siteUrl,
                topicId: topic.id,
                bookmark: bookmark,
              );
      if (context.mounted) _showWriteMessage(context, write);
    case _TopicBookmarksActionKind.clearAll:
      if (!await _confirm(
        context,
        title: 'Delete all bookmarks?',
        message: 'Every topic and post bookmark in this topic will be removed.',
        action: 'Delete all',
      )) {
        return;
      }
      final write = await controller.deleteAllTopicBookmarks(
        siteUrl: siteUrl,
        topicId: topic.id,
      );
      if (context.mounted) _showWriteMessage(context, write);
  }
}

Future<void> showBookmarkEditor({
  required BuildContext context,
  required BookmarkTargetHost controller,
  required String siteUrl,
  required int topicId,
  required Bookmark bookmark,
  String? cooked,
}) => showShellSheet<void>(
  context: context,
  title: 'Edit bookmark',
  dialogOnDesktop: true,
  builder: (_) => _BookmarkEditor(
    controller: controller,
    siteUrl: siteUrl,
    topicId: topicId,
    bookmark: bookmark,
    cooked: cooked,
  ),
);

class _BookmarkQuickSheet extends StatefulWidget {
  const _BookmarkQuickSheet({
    required this.controller,
    required this.siteUrl,
    required this.topicId,
    required this.targetId,
    required this.initialBookmark,
  });

  final BookmarkTargetHost controller;
  final String siteUrl;
  final int topicId;
  final int targetId;
  final Bookmark? initialBookmark;

  @override
  State<_BookmarkQuickSheet> createState() => _BookmarkQuickSheetState();
}

class _BookmarkQuickSheetState extends State<_BookmarkQuickSheet> {
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
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.controller.createBookmark(
      siteUrl: widget.siteUrl,
      topicId: widget.topicId,
      targetId: widget.targetId,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _bookmark = result.bookmark;
      _error = result.message;
    });
  }

  Future<void> _setReminder(DateTime reminder) async {
    final bookmark = _bookmark;
    if (bookmark == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.controller.updateBookmark(
      siteUrl: widget.siteUrl,
      topicId: widget.topicId,
      bookmark: bookmark,
      name: bookmark.name,
      reminderAt: reminder,
      autoDeletePreference: bookmark.autoDeletePreference,
    );
    if (!mounted) return;
    if (result.saved) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = result.message;
    });
  }

  Future<void> _clearReminder() async {
    final bookmark = _bookmark;
    if (bookmark == null) return;
    setState(() => _busy = true);
    final result = await widget.controller.clearBookmarkReminder(
      siteUrl: widget.siteUrl,
      topicId: widget.topicId,
      bookmark: bookmark,
    );
    if (!mounted) return;
    if (result.saved) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = result.message;
    });
  }

  Future<void> _delete() async {
    final bookmark = _bookmark;
    if (bookmark == null) return;
    if (bookmark.reminderAt != null &&
        !await _confirm(
          context,
          title: 'Delete bookmark?',
          message: 'This also removes its scheduled reminder.',
          action: 'Delete',
        )) {
      return;
    }
    setState(() => _busy = true);
    final result = await widget.controller.deleteBookmark(
      siteUrl: widget.siteUrl,
      topicId: widget.topicId,
      bookmark: bookmark,
    );
    if (!mounted) return;
    if (result.saved) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final siteContext = widget.controller.siteContextFor(widget.siteUrl);
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
          const LinearProgressIndicator(),
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
          Text(_busy ? 'Saving bookmark…' : 'The bookmark was not saved.')
        else if (widget.initialBookmark == null) ...[
          Text('Bookmarked!', style: Theme.of(context).textTheme.titleSmall),
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
            title: const Text('More options'),
            enabled: !_busy,
            onTap: _busy
                ? null
                : () => Navigator.of(
                    context,
                  ).pop(_QuickMenuResult.edit(bookmark)),
          ),
        ] else ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const DIcon(DIcons.pencil),
            title: const Text('Edit bookmark'),
            enabled: !_busy,
            onTap: _busy
                ? null
                : () => Navigator.of(
                    context,
                  ).pop(_QuickMenuResult.edit(bookmark)),
          ),
          if (bookmark.reminderAt != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const DIcon(DIcons.farClock),
              title: const Text('Clear reminder'),
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
              'Delete bookmark',
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
    required this.topicId,
    required this.bookmark,
    this.cooked,
  });

  final BookmarkTargetHost controller;
  final String siteUrl;
  final int topicId;
  final Bookmark bookmark;
  final String? cooked;

  @override
  State<_BookmarkEditor> createState() => _BookmarkEditorState();
}

class _BookmarkEditorState extends State<_BookmarkEditor> {
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
    final registry = PluginScope.of(context).registry;
    final siteContext = widget.controller.siteContextFor(widget.siteUrl);
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
    if (!mounted) return;
    setState(() {
      _lastCustom = last?.isAfter(DateTime.now()) == true ? last : null;
      _postDate = postDate;
    });
  }

  Future<void> _pickCustom() async {
    final environment = TimezoneEnvironment.instance;
    final siteContext = widget.controller.siteContextFor(widget.siteUrl);
    final zoneName = environment.readerTimezone(siteContext.timezone);
    final location = environment.location(zoneName)!;
    final wallInitial = tzDate(
      _reminder ?? DateTime.now().add(const Duration(hours: 1)),
      location,
    );
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(
        wallInitial.year,
        wallInitial.month,
        wallInitial.day,
      ),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3653)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: wallInitial.hour,
        minute: wallInitial.minute,
      ),
    );
    if (time == null) return;
    final instant = BookmarkReminderCalculator.resolveWallTime(
      location: location,
      date: date,
      hour: time.hour,
      minute: time.minute,
    );
    if (instant == null) {
      setState(
        () => _error =
            'That local time does not exist because of daylight saving time.',
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
      setState(() => _error = 'Enter a positive reminder duration.');
      return;
    }
    setState(() {
      _reminder = DateTime.now().add(_relativeUnit.duration(amount)).toUtc();
      _error = null;
    });
  }

  Future<void> _save() async {
    final now = DateTime.now().toUtc();
    final reminder = _reminder?.toUtc();
    if (reminder != null && !reminder.isAfter(now)) {
      setState(() => _error = 'Choose a reminder in the future.');
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
      setState(() => _error = 'Choose a reminder no more than 10 years away.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final text = _name.text.trim();
    final result = await widget.controller.updateBookmark(
      siteUrl: widget.siteUrl,
      topicId: widget.topicId,
      bookmark: widget.bookmark,
      name: text.isEmpty ? null : text,
      reminderAt: reminder,
      autoDeletePreference: _preference,
    );
    if (!mounted) return;
    if (result.saved) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _error = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final siteContext = widget.controller.siteContextFor(widget.siteUrl);
    final environment = TimezoneEnvironment.instance;
    final zoneName = environment.readerTimezone(siteContext.timezone);
    final location = environment.location(zoneName)!;
    final presets = BookmarkReminderCalculator.fullSuggestions(
      now: DateTime.now(),
      location: location,
      suggestWeekends: siteContext.suggestWeekendsInDatePickers,
    );

    return Form(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _name,
            maxLength: 100,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Note',
              hintText: 'Why are you saving this?',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<BookmarkAutoDeletePreference>(
            initialValue: _preference,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Afterward'),
            items: [
              for (final preference in BookmarkAutoDeletePreference.values)
                DropdownMenuItem(
                  value: preference,
                  child: Text(_preferenceLabel(preference)),
                ),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _preference = value!),
          ),
          const SizedBox(height: 20),
          Text('Remind me', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Times use $zoneName.',
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
                  label: const Text('Date in post'),
                  onPressed: _busy
                      ? null
                      : () => setState(() => _reminder = postDate),
                ),
              if (_lastCustom case final last?)
                ActionChip(
                  label: const Text('Last custom time'),
                  onPressed: _busy
                      ? null
                      : () => setState(() => _reminder = last),
                ),
              ActionChip(
                label: const Text('Custom date and time'),
                onPressed: _busy ? null : _pickCustom,
              ),
              ActionChip(
                label: const Text('No reminder'),
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
                  controller: _relative,
                  keyboardType: TextInputType.number,
                  enabled: !_busy,
                  decoration: const InputDecoration(labelText: 'In'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<_RelativeUnit>(
                  initialValue: _relativeUnit,
                  items: [
                    for (final unit in _RelativeUnit.values)
                      DropdownMenuItem(value: unit, child: Text(unit.label)),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _relativeUnit = value!),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _busy ? null : _setRelative,
                child: const Text('Set'),
              ),
            ],
          ),
          if (_reminder case final reminder?) ...[
            const SizedBox(height: 12),
            Text('Reminder: ${_formatReminder(context, reminder, zoneName)}'),
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
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Save'),
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
    required this.controller,
    required this.siteUrl,
    required this.topicId,
  });

  final BookmarkHost controller;
  final String siteUrl;
  final int topicId;

  @override
  Widget build(
    BuildContext context,
  ) => ShellSelector<({TopicDetail? topic, String busyTargets})>(
    select: (shell) {
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
        return const Text('This topic is no longer available.');
      }
      final siteContext = controller
          .bookmarkTarget(BookmarkTargetType.topic)
          .siteContextFor(siteUrl);
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
              topic.topicBookmark == null ? 'Bookmark topic' : 'Topic bookmark',
            ),
            subtitle: _bookmarkContext(context, topic.topicBookmark, zoneName),
            enabled: !topicBusy,
            onTap: topicBusy
                ? null
                : () => Navigator.of(context).pop(
                    const _TopicBookmarksAction(
                      _TopicBookmarksActionKind.topic,
                    ),
                  ),
          ),
          const Divider(),
          for (final bookmark in topic.postBookmarks)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: DIcon(
                bookmark.reminderAt == null
                    ? DIcons.bookmark
                    : DIcons.discourseBookmarkClock,
              ),
              title: Text('Post #${bookmark.postNumber ?? '?'}'),
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
                  : () => Navigator.of(context).pop(
                      _TopicBookmarksAction(
                        _TopicBookmarksActionKind.jump,
                        postNumber: bookmark.postNumber,
                      ),
                    ),
              trailing: PopupMenuButton<_TopicBookmarksActionKind>(
                tooltip: 'Post bookmark actions',
                enabled: !snapshot.busyTargets
                    .split(',')
                    .contains('${bookmark.bookmarkableId}'),
                itemBuilder: (_) => [
                  if (bookmark.postNumber != null)
                    const PopupMenuItem(
                      value: _TopicBookmarksActionKind.jump,
                      child: Text('Jump'),
                    ),
                  const PopupMenuItem(
                    value: _TopicBookmarksActionKind.edit,
                    child: Text('Edit'),
                  ),
                  const PopupMenuItem(
                    value: _TopicBookmarksActionKind.delete,
                    child: Text('Delete'),
                  ),
                ],
                onSelected: (kind) => Navigator.of(context).pop(
                  _TopicBookmarksAction(
                    kind,
                    bookmark: bookmark,
                    postNumber: kind == _TopicBookmarksActionKind.jump
                        ? bookmark.postNumber
                        : null,
                  ),
                ),
              ),
            ),
          if (topic.bookmarks.length > 1) ...[
            const Divider(),
            TextButton.icon(
              onPressed: snapshot.busyTargets.isNotEmpty
                  ? null
                  : () => Navigator.of(context).pop(
                      const _TopicBookmarksAction(
                        _TopicBookmarksActionKind.clearAll,
                      ),
                    ),
              icon: const DIcon(DIcons.trashCan),
              label: const Text('Delete all bookmarks'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
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
      'Reminder: ${_formatReminder(context, reminder, zoneName)}',
  ];
  if (lines.isEmpty) return null;
  return Text(lines.join('\n'), maxLines: 3, overflow: TextOverflow.ellipsis);
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async =>
    await showDiscourseDialog<bool>(
      context: context,
      builder: (context) => DiscourseAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          AdaptiveDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          AdaptiveDialogAction(
            kind: AdaptiveDialogActionKind.destructive,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

void _showWriteMessage(BuildContext context, BookmarkWriteResult result) {
  if (result.message case final message?) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }
}

String _preferenceLabel(BookmarkAutoDeletePreference preference) =>
    switch (preference) {
      BookmarkAutoDeletePreference.never => 'Keep bookmark',
      BookmarkAutoDeletePreference.whenReminderSent =>
        'Delete after the reminder',
      BookmarkAutoDeletePreference.onOwnerReply => 'Delete once I reply',
      BookmarkAutoDeletePreference.clearReminder =>
        'Keep bookmark and clear reminder',
    };

String _formatReminder(
  BuildContext context,
  DateTime instant,
  String zoneName,
) {
  final environment = TimezoneEnvironment.instance;
  final wall = tzDate(instant, environment.location(zoneName)!);
  final localizations = MaterialLocalizations.of(context);
  return '${localizations.formatMediumDate(wall)} at '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(wall))}';
}

tz.TZDateTime tzDate(DateTime instant, tz.Location location) {
  // Kept at this seam so the UI never relies on the device-local DateTime zone.
  return tz.TZDateTime.from(instant, location);
}
