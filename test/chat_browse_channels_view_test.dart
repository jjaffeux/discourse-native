import 'dart:async';

import 'package:discourse_native/discourse_ui.dart'
    show DButton, DDropdownMenuItem, DSpacing, DSpinner, DSkeletonRegion;
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugins/chat/chat_browse_channels_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_browse_navigation.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/fakes.dart';
import 'support/shell_test_harness.dart';

const _site = 'https://meta.discourse.org';
const _user = DiscourseUser(id: 7, username: 'joffreyj');
const _emptyMessage = 'No channels match these filters.';

void main() {
  group('ChatBrowseChannelsView', () {
    testWidgets('filters and channel cards follow the content size setting', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = _BrowseApi(
        chatBrowsePagesByKey: {
          FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
            channels: [_channel(1)],
          ),
        },
      );
      final controller = await _pumpBrowse(tester, api);
      final filter = find
          .descendant(
            of: find.byType(ContentReadingLaneBox).first,
            matching: find.byType(Column),
          )
          .first;
      final card = _card(1);

      for (final limited in [false, true, false]) {
        await controller.appSettings.setLimitContentSize(limited);
        await tester.pumpAndSettle();
        final filterRect = tester.getRect(filter);
        final cardRect = tester.getRect(card);
        expect(filterRect.left, closeTo(cardRect.left, 0.01));
        expect(filterRect.width, closeTo(cardRect.width, 0.01));
        expect(filterRect.width, closeTo(limited ? 825 : 1368, 0.01));
      }
    });

    testWidgets('advances by server rows after filtering malformed channels', (
      tester,
    ) async {
      final api = _BrowseApi(
        chatBrowsePagesByKey: {
          FakeDiscourseApi.chatBrowseKey(): _decodedPage([
            _channelJson(1),
            ...List<Object?>.filled(24, null),
          ]),
          FakeDiscourseApi.chatBrowseKey(offset: 25): _decodedPage([
            _channelJson(2),
          ]),
        },
      );
      await _pumpBrowse(tester, api);

      expect(_card(1), findsOneWidget);
      expect(find.text('Load more'), findsOneWidget);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect(_offsets(api), [0, 25]);
      expect(_card(2), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
    });

    testWidgets('pages and retries while all received channels are filtered', (
      tester,
    ) async {
      final api = _BrowseApi(
        chatBrowsePagesByKey: {
          FakeDiscourseApi.chatBrowseKey(): _decodedPage(
            List<Object?>.filled(25, null),
          ),
          FakeDiscourseApi.chatBrowseKey(offset: 50): _decodedPage([
            _channelJson(3),
          ]),
        },
      );
      await _pumpBrowse(tester, api);

      expect(find.text(_emptyMessage), findsNothing);
      expect(find.text('Load more'), findsOneWidget);
      expect(_offsets(api), [0]);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect(find.text('Try again'), findsOneWidget);
      expect(_offsets(api), [0, 25]);
      api.chatBrowsePagesByKey[FakeDiscourseApi.chatBrowseKey(offset: 25)] =
          _decodedPage(List<Object?>.filled(25, false));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text(_emptyMessage), findsNothing);
      expect(find.text('Load more'), findsOneWidget);
      expect(_offsets(api), [0, 25, 25]);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect(_card(3), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      expect(_offsets(api), [0, 25, 25, 50]);
    });

    testWidgets('a failed page waits for Try again instead of scrolling', (
      tester,
    ) async {
      final api = _BrowseApi(
        chatBrowsePagesByKey: {
          FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
            channels: [
              for (var id = 1; id <= ChatChannelBrowsePage.pageSize; id++)
                _channel(id),
            ],
            hasMore: true,
          ),
        },
      );
      await _pumpBrowse(tester, api);
      expect(_offsets(api), [0]);

      final list = find.byKey(const PageStorageKey('chat-browse-channels'));
      await tester.fling(list, const Offset(0, -6000), 6000);
      await tester.pumpAndSettle();
      for (var drag = 0; drag < 5; drag++) {
        await tester.drag(list, const Offset(0, 40));
        await tester.drag(list, const Offset(0, -40));
        await tester.pumpAndSettle();
      }

      const nextPage = ChatChannelBrowsePage.pageSize;
      expect(_offsets(api), [0, nextPage]);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(_offsets(api), [0, nextPage, nextPage]);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('stops a zero-row page even if marked nonterminal', (
      tester,
    ) async {
      final api = _BrowseApi(
        chatBrowsePagesByKey: {
          FakeDiscourseApi.chatBrowseKey(): const ChatChannelBrowsePage(
            hasMore: true,
          ),
        },
      );
      await _pumpBrowse(tester, api);

      expect(find.text(_emptyMessage), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      expect(_offsets(api), [0]);
    });

    for (final joined in [true, false]) {
      final membership = joined ? 'Joined' : 'Not joined';

      testWidgets('$membership can reach matches after a hidden first page', (
        tester,
      ) async {
        final api = _BrowseApi(
          chatBrowsePagesByKey: {
            FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
              channels: [
                _channel(1, following: !joined),
                _channel(2, following: !joined),
              ],
              hasMore: true,
            ),
            FakeDiscourseApi.chatBrowseKey(offset: 2): ChatChannelBrowsePage(
              channels: [_channel(3, following: joined)],
            ),
          },
        );
        await _pumpBrowse(tester, api);
        await _selectMembership(tester, membership);

        expect(_card(1), findsNothing);
        expect(_card(2), findsNothing);
        expect(find.text(_emptyMessage), findsNothing);
        expect(find.text('Load more'), findsOneWidget);
        expect(_offsets(api), [0]);

        await tester.tap(find.text('Load more'));
        await tester.pumpAndSettle();

        expect(_card(3), findsOneWidget);
        expect(find.text('Load more'), findsNothing);
        expect(_offsets(api), [0, 2]);

        await _selectMembership(tester, 'All');

        expect(_card(1), findsOneWidget);
        expect(_card(2), findsOneWidget);
        expect(_card(3), findsOneWidget);
        expect(_offsets(api), [0, 2]);
      });

      testWidgets('$membership can page after changing the last visible row', (
        tester,
      ) async {
        final api = _BrowseApi(
          chatBrowsePagesByKey: {
            FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
              channels: [_channel(1, following: joined)],
              hasMore: true,
            ),
            FakeDiscourseApi.chatBrowseKey(offset: 1): ChatChannelBrowsePage(
              channels: [_channel(2, following: joined)],
            ),
          },
        );
        await _pumpBrowse(tester, api);
        await _selectMembership(tester, membership);

        await tester.tap(
          find.byKey(ValueKey(joined ? 'chat-unfollow-1' : 'chat-join-1')),
        );
        await tester.pumpAndSettle();

        expect(api.chatChannelFollowsUpdated, [
          (channelId: 1, following: !joined),
        ]);
        expect(_card(1), findsNothing);
        expect(find.text('Load more'), findsOneWidget);
        expect(_offsets(api), [0]);

        await tester.tap(find.text('Load more'));
        await tester.pumpAndSettle();

        expect(_card(2), findsOneWidget);
        expect(_offsets(api), [0, 1]);
      });
    }

    testWidgets('keeps paging explicitly across consecutive hidden pages', (
      tester,
    ) async {
      final api = _BrowseApi(
        chatBrowsePagesByKey: {
          for (var offset = 0; offset < 3; offset++)
            FakeDiscourseApi.chatBrowseKey(
              offset: offset,
            ): ChatChannelBrowsePage(
              channels: [_channel(offset + 1)],
              hasMore: offset < 2,
            ),
        },
      );
      await _pumpBrowse(tester, api);
      await _selectMembership(tester, 'Joined');

      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect(find.text('Load more'), findsOneWidget);
      expect(find.text(_emptyMessage), findsNothing);
      expect(_offsets(api), [0, 1]);

      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect(find.text(_emptyMessage), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      expect(find.text('Try again'), findsNothing);
      expect(_offsets(api), [0, 1, 2]);
    });

    testWidgets('retries a failed hidden page at the same server offset', (
      tester,
    ) async {
      final api = _BrowseApi(
        chatBrowsePagesByKey: {
          FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
            channels: [_channel(1), _channel(2)],
            hasMore: true,
          ),
        },
      );
      await _pumpBrowse(tester, api);
      await _selectMembership(tester, 'Joined');

      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();

      expect(find.text('Try again'), findsOneWidget);
      expect(find.text(_emptyMessage), findsNothing);
      expect(_offsets(api), [0, 2]);

      await _selectMembership(tester, 'All');
      expect(_card(1), findsOneWidget);
      expect(_card(2), findsOneWidget);
      await _selectMembership(tester, 'Joined');

      api.chatBrowsePagesByKey[FakeDiscourseApi.chatBrowseKey(offset: 2)] =
          ChatChannelBrowsePage(channels: [_channel(3, following: true)]);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(_card(3), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(_offsets(api), [0, 2, 2]);
    });

    testWidgets('pull does not refresh an exhausted empty filtered result', (
      tester,
    ) async {
      final api = _BrowseApi(
        chatBrowsePagesByKey: {
          FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
            channels: [_channel(1)],
          ),
        },
      );
      await _pumpBrowse(tester, api);
      await _selectMembership(tester, 'Joined');

      expect(find.text(_emptyMessage), findsOneWidget);
      expect(find.text('Load more'), findsNothing);

      api.chatBrowsePagesByKey[FakeDiscourseApi.chatBrowseKey()] =
          ChatChannelBrowsePage(channels: [_channel(2, following: true)]);
      await tester.drag(find.byType(ListView), const Offset(0, 350));
      await tester.pumpAndSettle();

      expect(_card(2), findsNothing);
      expect(find.text(_emptyMessage), findsOneWidget);
      expect(_offsets(api), [0]);
    });

    testWidgets('retries an initial failure from offset zero', (tester) async {
      final api = _BrowseApi(chatBrowsePagesByKey: {});
      await _pumpBrowse(tester, api);

      expect(find.text('Try again'), findsOneWidget);
      api.chatBrowsePagesByKey[FakeDiscourseApi.chatBrowseKey()] =
          const ChatChannelBrowsePage();
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text(_emptyMessage), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Load more'), findsNothing);
      expect(_offsets(api), [0, 0]);
    });

    testWidgets('admits only one next-page request while rows are hidden', (
      tester,
    ) async {
      final api = _BrowseApi(
        chatBrowsePagesByKey: {
          FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
            channels: [_channel(1)],
            hasMore: true,
          ),
          FakeDiscourseApi.chatBrowseKey(offset: 1): ChatChannelBrowsePage(
            channels: [_channel(2, following: true)],
          ),
        },
      );
      final gate = _holdPage(api, offset: 1);
      await _pumpBrowse(tester, api);
      await _selectMembership(tester, 'Joined');

      await tester.tap(find.text('Load more'));
      await tester.tap(find.text('Load more'));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -100));
      await tester.pump();

      expect(find.byType(DSpinner), findsNothing);
      expect(find.byType(DSkeletonRegion), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      expect(_offsets(api), [0, 1]);

      gate.complete();
      await tester.pumpAndSettle();

      expect(_card(2), findsOneWidget);
      expect(_offsets(api), [0, 1]);
    });

    testWidgets('ignores a hidden page that finishes after a filter reset', (
      tester,
    ) async {
      final api = _BrowseApi(
        chatBrowsePagesByKey: {
          FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
            channels: [_channel(1)],
            hasMore: true,
          ),
          FakeDiscourseApi.chatBrowseKey(offset: 1): ChatChannelBrowsePage(
            channels: [_channel(2, following: true)],
            hasMore: true,
          ),
          FakeDiscourseApi.chatBrowseKey(filter: 'new'): ChatChannelBrowsePage(
            channels: [_channel(3, following: true)],
          ),
        },
      );
      final gate = _holdPage(api, offset: 1);
      await _pumpBrowse(tester, api);
      await _selectMembership(tester, 'Joined');
      await tester.tap(find.text('Load more'));
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('chat-browse-filter')),
        'new',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(_card(3), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();

      expect(_card(1), findsNothing);
      expect(_card(2), findsNothing);
      expect(_card(3), findsOneWidget);
      expect(find.text('Load more'), findsNothing);
      expect(api.chatBrowseRequested, [
        for (final (filter, offset) in [('', 0), ('', 1), ('new', 0)])
          (
            filter: filter,
            status: ChatChannelBrowseStatus.all,
            offset: offset,
            limit: ChatChannelBrowsePage.pageSize,
          ),
      ]);
    });

    testWidgets('focusing the filter keeps the pages already loaded', (
      tester,
    ) async {
      final api = _BrowseApi(
        chatBrowsePagesByKey: {
          FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
            channels: [_channel(1)],
            hasMore: true,
          ),
          FakeDiscourseApi.chatBrowseKey(offset: 1): ChatChannelBrowsePage(
            channels: [_channel(2)],
          ),
        },
      );
      await _pumpBrowse(tester, api);
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(_offsets(api), [0, 1]);
      final text = _filterText(tester);
      final before = text.selection;

      await tester.tap(_filter);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(text.text, isEmpty);
      expect(text.selection, isNot(before));
      expect(_offsets(api), [0, 1]);
      expect(_card(1), findsOneWidget);
      expect(_card(2), findsOneWidget);
    });

    testWidgets('moving the cursor keeps the filtered pages already loaded', (
      tester,
    ) async {
      final api = _BrowseApi(
        chatBrowsePagesByKey: {
          FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
            channels: [_channel(1), _channel(2)],
          ),
          FakeDiscourseApi.chatBrowseKey(filter: 'new'): ChatChannelBrowsePage(
            channels: [_channel(3)],
            hasMore: true,
          ),
          FakeDiscourseApi.chatBrowseKey(filter: 'new', offset: 1):
              ChatChannelBrowsePage(channels: [_channel(4)]),
        },
      );
      await _pumpBrowse(tester, api);

      await tester.enterText(_filter, 'new');
      await tester.pump(const Duration(milliseconds: 349));
      expect(api.chatBrowseRequested, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load more'));
      await tester.pumpAndSettle();
      expect(_card(3), findsOneWidget);
      expect(_card(4), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(
        _filterText(tester).value,
        const TextEditingValue(
          text: 'new',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      expect(_card(3), findsOneWidget);
      expect(_card(4), findsOneWidget);
      expect(api.chatBrowseRequested, hasLength(3));

      await tester.enterText(_filter, '');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(_card(1), findsOneWidget);
      expect(_card(2), findsOneWidget);
      expect(_card(3), findsNothing);
      expect(_card(4), findsNothing);
      expect(api.chatBrowseRequested, [
        for (final (filter, offset) in [
          ('', 0),
          ('new', 0),
          ('new', 1),
          ('', 0),
        ])
          (
            filter: filter,
            status: ChatChannelBrowseStatus.all,
            offset: offset,
            limit: ChatChannelBrowsePage.pageSize,
          ),
      ]);
    });
  });

  group('ChatBrowseChannelsView on a phone', () {
    _mobileTest(
      'a normal height keeps the filters fixed above the scrolling channels',
      (tester) async {
        final api = await _pumpMobileBrowse(tester, phone);
        final filter = tester.getRect(_filter);
        final card = tester.getRect(_card(3));
        expect(tester.getRect(_list).bottom, tester.getRect(_browse).bottom);

        await tester.drag(_list, const Offset(0, -200));
        await tester.pumpAndSettle();
        expect(tester.getRect(_card(3)).top, lessThan(card.top));
        expect(tester.getRect(_filter), filter);

        await tester.fling(_list, const Offset(0, -6000), 6000);
        await tester.pumpAndSettle();
        expect(_offsets(api), [0, ChatChannelBrowsePage.pageSize]);
        expect(tester.getRect(_filter), filter);
        expect(tester.takeException(), isNull);
      },
    );

    _mobileTest(
      'a keyboard over large text on a narrow phone keeps the filters usable '
      'at the top',
      (tester) async {
        final api = await _pumpShortBrowse(tester);
        final browse = tester.getRect(_browse);
        expect(_list, findsNothing);
        await tester.ensureVisible(_filter);
        await tester.pumpAndSettle();
        expect(tester.getRect(_filter).top, greaterThanOrEqualTo(browse.top));
        expect(
          tester.getRect(_filter).bottom,
          lessThanOrEqualTo(browse.bottom),
        );
        expect(_filter.hitTestable(), findsOneWidget);

        api.chatBrowsePagesByKey[FakeDiscourseApi.chatBrowseKey(
          filter: 'Channel',
        )] = ChatChannelBrowsePage(
          channels: [_channel(1, following: true), _channel(2)],
        );
        await tester.enterText(_filter, 'Channel');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(api.chatBrowseRequested.last.filter, 'Channel');
        expect(_card(2), findsOneWidget);
        expect(_card(3), findsNothing);

        // Doubled text wraps the label, so the trigger is the value below it.
        final membership = find.descendant(
          of: _joined,
          matching: find.text('Membership'),
        );
        await tester.ensureVisible(membership);
        await tester.pumpAndSettle();
        await tester.tap(membership);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.inMutuallyExclusiveGroup == true &&
                widget.properties.label == 'Joined',
          ),
        );
        await tester.pumpAndSettle();
        expect(_card(1), findsOneWidget);
        expect(_card(2), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    _mobileTest(
      'a keyboard over large text on a narrow phone scrolls the filters away '
      'to reach every channel and Load more',
      (tester) async {
        final api = await _pumpShortBrowse(tester);
        final browse = tester.getRect(_browse);
        final loadMore = find.widgetWithText(DButton, 'Load more');

        for (final target in [
          _card(ChatChannelBrowsePage.pageSize),
          loadMore,
        ]) {
          await tester.scrollUntilVisible(target, 100, scrollable: _scrollable);
          final rect = tester.getRect(target);
          expect(rect.top, greaterThanOrEqualTo(browse.top));
          expect(rect.bottom, lessThanOrEqualTo(browse.bottom));
          expect(target.hitTestable(), findsOneWidget);
        }
        expect(tester.getRect(_filter).bottom, lessThan(browse.top));
        expect(_offsets(api), [0]);

        await tester.tap(loadMore);
        await tester.pumpAndSettle();
        expect(_offsets(api), [0, ChatChannelBrowsePage.pageSize]);
        expect(_card(ChatChannelBrowsePage.pageSize + 1), findsOneWidget);
        expect(loadMore, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    _mobileTest(
      'dismissing the keyboard fixes the filters above the channels again',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pumpMobileBrowse(tester, const Size(320, 720));
        final filter = tester.getRect(_filter);
        final list = tester.getRect(_list);
        expect(list.bottom, tester.getRect(_browse).bottom);

        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await tester.drag(_filter, const Offset(0, -150));
        await tester.pumpAndSettle();
        expect(tester.getRect(_filter).top, lessThan(filter.top));

        tester.view.resetViewInsets();
        await tester.pumpAndSettle();

        expect(tester.getRect(_filter), filter);
        expect(tester.getRect(_list), list);
        expect(tester.takeException(), isNull);
      },
    );

    for (final (size, scale) in [(phone, 1.0), (const Size(320, 720), 2.0)]) {
      _mobileTest(
        'at ${size.width.toInt()}x${size.height.toInt()} with ${scale}x text '
        'each filter opens from anywhere on its touch target',
        (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await _pumpMobileBrowse(tester, size);

          for (final (select, label, option) in [
            (_status, 'Status', 'Archived'),
            (_joined, 'Membership', 'Not joined'),
          ]) {
            await tester.ensureVisible(select);
            final target = tester.getRect(
              find.descendant(of: select, matching: find.byType(DButton)),
            );
            expect(target.height, greaterThanOrEqualTo(DSpacing.touchTarget));
            expect(
              find.descendant(of: select, matching: find.text(label)),
              findsOneWidget,
            );
            for (final point in [
              target.center,
              target.topCenter + const Offset(0, 1),
              target.bottomCenter - const Offset(0, 1),
            ]) {
              await tester.tapAt(point);
              await tester.pumpAndSettle();
              expect(find.text(option), findsOneWidget, reason: '$point');
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
              await tester.pumpAndSettle();
              expect(find.text(option), findsNothing);
            }
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  });
}

final _browse = find.byType(ChatBrowseChannelsView);
final _filter = find.byKey(const ValueKey('chat-browse-filter'));
final _status = find.byKey(const ValueKey('chat-browse-status'));
final _joined = find.byKey(const ValueKey('chat-browse-joined'));
final _list = find.byKey(const PageStorageKey('chat-browse-channels'));
final _scrollable = find
    .descendant(of: _browse, matching: find.byType(Scrollable))
    .first;

void _mobileTest(String name, WidgetTesterCallback callback) => testWidgets(
  name,
  callback,
  variant: const TargetPlatformVariant({
    TargetPlatform.iOS,
    TargetPlatform.android,
  }),
);

/// The production mobile shell on Browse channels, with more channels than a
/// phone shows at once and a further page behind them.
Future<_BrowseApi> _pumpMobileBrowse(WidgetTester tester, Size size) async {
  final user = DiscourseUser(
    id: 7,
    username: 'joffreyj',
    plugins: PluginData.none.withValue(
      chatCurrentUserDataKey,
      const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
    ),
  );
  final config = SiteConfig(
    plugins: PluginData.none.withValue(
      chatSettingsDataKey,
      const ChatSettings(chatEnabled: true, publicChannelsEnabled: true),
    ),
  );
  final api = _BrowseApi(
    user: user,
    totals: chatNotificationTotals(),
    siteConfigs: {_site: config},
    feeds: const {'/latest.json': []},
    chatChannelsBySite: {
      _site: ChatChannels(public: [_channel(1, following: true)]),
    },
    chatBrowsePagesByKey: {
      FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
        channels: [
          for (var id = 1; id <= ChatChannelBrowsePage.pageSize; id++)
            _channel(id, following: id == 1),
        ],
        hasMore: true,
      ),
      FakeDiscourseApi.chatBrowseKey(
        offset: ChatChannelBrowsePage.pageSize,
      ): ChatChannelBrowsePage(
        channels: [_channel(ChatChannelBrowsePage.pageSize + 1)],
      ),
    },
  );
  await pumpShell(
    tester,
    size,
    instances: [
      instance(
        'meta.discourse.org',
        title: 'Meta',
      ).copyWith(user: user, config: config),
    ],
    authenticator: FakeAuthenticator()..keys[_site] = 'key',
    api: api,
  );
  // Enlarged text on a narrow phone moves Chat into the dock's More menu.
  final dockTab = find.byKey(const ValueKey('mobile-mode-panel/chat'));
  if (dockTab.evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('mobile-mode-more')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(DDropdownMenuItem),
        matching: find.text('Chat'),
      ),
    );
  } else {
    await tester.tap(dockTab);
  }
  await tester.pumpAndSettle();
  final channelsTab = find.byKey(
    const ValueKey(('toggle-group-item', ChatBrowsePage.channels)),
  );
  await tester.ensureVisible(channelsTab);
  await tester.tap(channelsTab);
  await tester.pumpAndSettle();
  expect(_browse, findsOneWidget);
  return api;
}

/// Browse channels on a 320x720 phone with doubled text under a 280px
/// keyboard, which leaves the channels no room below the filters.
Future<_BrowseApi> _pumpShortBrowse(WidgetTester tester) async {
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final api = await _pumpMobileBrowse(tester, const Size(320, 720));
  tester.view.viewInsets = const FakeViewPadding(bottom: 280);
  addTearDown(tester.view.resetViewInsets);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return api;
}

ChatChannel _channel(int id, {bool following = false}) => ChatChannel(
  id: id,
  title: 'Channel $id',
  kind: ChatChannelKind.category,
  canJoin: true,
  membership: ChatMembership(following: following),
);

ChatChannelBrowsePage _decodedPage(List<Object?> rows) =>
    ChatChannelBrowsePage.fromJson({
      'channels': rows,
      'meta': const {'load_more_url': '/next'},
    }, _site);

Map<String, Object?> _channelJson(int id) => {
  'id': id,
  'title': 'Channel $id',
  'chatable_type': 'Category',
};

Finder _card(int id) => find.byKey(ValueKey('chat-browse-channel-$id'));

TextEditingController _filterText(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(of: _filter, matching: find.byType(EditableText)),
    )
    .controller;

Iterable<int> _offsets(FakeDiscourseApi api) =>
    api.chatBrowseRequested.map((request) => request.offset);

Future<void> _selectMembership(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(const ValueKey('chat-browse-joined')));
  await tester.pumpAndSettle();
  await tester.tap(
    find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.inMutuallyExclusiveGroup == true &&
          widget.properties.label == label,
    ),
  );
  await tester.pumpAndSettle();
}

Future<ShellController> _pumpBrowse(
  WidgetTester tester,
  FakeDiscourseApi api,
) async {
  final authenticator = FakeAuthenticator()..keys[_site] = 'key';
  final controller = ShellController(
    plugins: installedPlugins,
    instanceStore: FakeInstanceStore([
      instance('meta.discourse.org').copyWith(user: _user),
    ]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  addTearDown(controller.dispose);
  await controller.load();
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: ContentSettingsScope(
        controller: controller.appSettings,
        child: PluginUiScope.own(
          chatPluginId,
          MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: ChatBrowseChannelsView(siteUrl: _site)),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Completer<void> _holdPage(_BrowseApi api, {required int offset}) {
  final gate = Completer<void>();
  api.gates[FakeDiscourseApi.chatBrowseKey(offset: offset)] = gate;
  addTearDown(() {
    if (!gate.isCompleted) gate.complete();
  });
  return gate;
}

class _BrowseApi extends FakeDiscourseApi {
  _BrowseApi({
    required super.chatBrowsePagesByKey,
    super.user = _user,
    super.totals,
    super.siteConfigs,
    super.feeds,
    super.chatChannelsBySite,
  });

  final gates = <String, Completer<void>>{};

  @override
  Future<ChatChannelBrowsePage> browseChatChannels({
    required String siteUrl,
    required String apiKey,
    String filter = '',
    ChatChannelBrowseStatus status = ChatChannelBrowseStatus.all,
    int offset = 0,
    int limit = ChatChannelBrowsePage.pageSize,
    String? clientId,
  }) async {
    final page = await super.browseChatChannels(
      siteUrl: siteUrl,
      apiKey: apiKey,
      filter: filter,
      status: status,
      offset: offset,
      limit: limit,
      clientId: clientId,
    );
    await gates[FakeDiscourseApi.chatBrowseKey(
          filter: filter,
          status: status,
          offset: offset,
        )]
        ?.future;
    return page;
  }
}
