import 'dart:math';
import 'package:discourse_native/src/models/account_feed_window.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_activity.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_list.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_list_preferences.dart';
import 'package:discourse_native/src/plugins/poll/poll.dart';
import 'package:discourse_native/src/plugins/poll/poll_ballot_draft.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/perf_round_three_model_workloads.dart';

const baseline = bool.fromEnvironment('PERF_BASELINE');
void main() {
  test('channel alphabetical projection reads each sort name once', () {
    final counts = _Counts();
    final channels = [for (var i = 0; i < 100; i++) _CountedChannel(i, counts)]
      ..shuffle(Random(61));
    final result = projectChatChannelList(
      channels,
      filter: ChatChannelListFilter.all,
      sort: ChatChannelListSort.alphabetical,
      section: ChatChannelListSection.channels,
      now: DateTime.utc(2026),
    );
    expect(result.map((channel) => channel.id), List.generate(100, (i) => i));
    if (!baseline) expect(counts.reads, lessThanOrEqualTo(100));
    // ignore: avoid_print
    print('WORK channel_sort_name_reads=${counts.reads}');
    expect(() => result.add(channels.first), throwsUnsupportedError);
    const replacement = ChatChannel(
      id: 0,
      title: 'Changed',
      kind: ChatChannelKind.category,
      slug: 'zzzz',
    );
    final updated = projectChatChannelList(
      [replacement, ...channels.where((channel) => channel.id != 0)],
      filter: ChatChannelListFilter.all,
      sort: ChatChannelListSort.alphabetical,
      section: ChatChannelListSection.channels,
      now: DateTime.utc(2026),
    );
    expect(updated.last, same(replacement));
  });
  test('category estimates are shared only within one activity operation', () {
    final counts = _Counts();
    final category = _CountedCategory(counts);
    final source = modelActivityFeed(300, category: category);
    final before = source.estimatedRetainedBytes;
    if (!baseline) expect(counts.reads, 1);
    // ignore: avoid_print
    print('WORK activity_estimate_category_reads=${counts.reads}');
    counts.reads = 0;
    final updated = source.withPage(
      UserActivityPage(
        items: [modelActivity(300)],
        categories: [category],
        rawItemCount: 1,
      ),
      limit: 30,
      replace: false,
    );
    expect(updated.items.last.topicId, 300);
    expect(updated.nextOffset, 301);
    if (!baseline) expect(counts.reads, 1);
    // ignore: avoid_print
    print('WORK activity_append_category_reads=${counts.reads}');
    final changed = source.withPage(
      UserActivityPage(
        items: [modelActivity(300)],
        categories: const [
          TopicCategory(
            id: 1,
            name: 'A much longer replaced category name',
            color: '336699',
          ),
        ],
        rawItemCount: 1,
      ),
      limit: 30,
      replace: false,
    );
    expect(changed.estimatedRetainedBytes, greaterThan(before ~/ 2));
    expect(
      changed.categoriesById[1]!.name,
      'A much longer replaced category name',
    );
  });
  test(
    'window deletion preserves data, cursor shifts and immutable ownership',
    () {
      final input = List.generate(30, (i) => i);
      final packets = [
        for (var page = 0; page < 9; page++)
          AccountFeedPacket<int>(
            start: page * 30,
            end: (page + 1) * 30,
            items: page == 0 ? input : List.generate(30, (i) => page * 30 + i),
          ),
      ];
      final window = AccountFeedWindow<int>(
        packets: packets,
        lastPageWasPrevious: true,
      );
      input.clear();
      final deleted = window.without(0, (i) => i);
      expect(deleted.items, List.generate(269, (i) => i + 1));
      expect(deleted.lastPageWasPrevious, isTrue);
      expect(deleted.packets.map((packet) => (packet.start, packet.end)), [
        (0, 29),
        for (var page = 1; page < 9; page++)
          (page * 30 - 1, (page + 1) * 30 - 1),
      ]);
      final retained = [
        for (var i = 1; i < 9; i++)
          if (identical(deleted.packets[i].items, packets[i].items)) i,
      ].length;
      if (!baseline) expect(retained, 8);
      // ignore: avoid_print
      print('WORK deletion_retained_row_lists=$retained');
      expect(() => deleted.packets[1].items.add(3), throwsUnsupportedError);
      final untouched = window.without(999, (i) => i);
      expect(untouched.items, window.items);
      if (!baseline) expect(untouched.packets.first, same(packets.first));
      packets.clear();
      expect(untouched.items, List.generate(270, (i) => i));
      expect(() => untouched.packets.clear(), throwsUnsupportedError);
      final duplicates = AccountFeedWindow<int>(
        packets: [
          AccountFeedPacket(start: 3, end: 7, items: const [1, 2, 1, 3]),
        ],
      ).without(1, (i) => i);
      expect(duplicates.items, [2, 3]);
      expect((duplicates.start, duplicates.end), (3, 5));
    },
  );
  test(
    'same poll reconciliation avoids option scans and retains mutable semantics',
    () {
      final counts = _Counts();
      final options = [
        for (var i = 0; i < 100; i++) PollOption(id: '$i', html: 'Option $i'),
      ];
      final poll = _CountedPoll(options, counts);
      final draft = PollBallotDraft(poll);
      counts.reads = 0;
      final reconciled = draft.reconcile(poll);
      expect(reconciled.selection, isEmpty);
      if (!baseline) expect(counts.reads, 0);
      // ignore: avoid_print
      print('WORK unchanged_empty_poll_option_reads=${counts.reads}');
      var chosen = PollBallotDraft(poll, selection: ['0', '1']);
      options.removeAt(0);
      chosen = chosen.reconcile(poll);
      expect(chosen.selection, {'1'});
      options.clear();
      expect(chosen.reconcile(poll).selection, isEmpty);
      final saved = ['0'];
      final mutableSaved = Poll(
        name: 'mutable',
        selection: PollSelection(optionIds: saved),
        options: const [PollOption(id: '0', html: 'Zero')],
      );
      final withdrawal = PollBallotDraft(mutableSaved, selection: const []);
      saved.clear();
      expect(withdrawal.reconcile(mutableSaved).submission, isNull);
    },
  );
  test('model workloads consume complete validated results', () {
    final times = measureRoundThreeModelPerformance();
    expect(times.length, 11);
    expect(times.values, everyElement(greaterThan(0)));
    // ignore: avoid_print
    print('MODEL_WORKLOADS $times');
  });
}

class _Counts {
  int reads = 0;
}

class _CountedChannel extends ChatChannel {
  _CountedChannel(int id, this.counts)
    : super(
        id: id,
        title: 'Room $id',
        kind: ChatChannelKind.category,
        slug: 'room-${id.toString().padLeft(4, '0')}',
      );
  final _Counts counts;
  @override
  String? get slug {
    counts.reads++;
    return super.slug;
  }
}

class _CountedCategory extends TopicCategory {
  const _CountedCategory(this.counts)
    : super(id: 1, name: 'Engineering', color: '336699');
  final _Counts counts;
  @override
  String get name {
    counts.reads++;
    return super.name;
  }
}

class _CountedPoll extends Poll {
  const _CountedPoll(List<PollOption> options, this.counts)
    : super(name: 'poll', options: options);
  final _Counts counts;
  @override
  List<PollOption> get options {
    counts.reads++;
    return super.options;
  }
}
