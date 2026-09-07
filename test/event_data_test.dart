import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/event_fixtures.dart';

void main() {
  test('absent and malformed records do not affect independent oneboxes', () {
    expect(EventPostData.decode({}), isNull);
    expect(EventPostData.decode({'event': null}), isNull);
    final data = EventPostData.decode({
      'event': {'id': 'bad'},
      'event_oneboxes': {
        '700': eventJson(),
        '701': {'id': null},
        '702': eventJson(),
        'not-an-id': eventJson(),
      },
    });
    expect(data!.event, isNull);
    expect(data.oneboxes.keys, [700]);
    expect(data.oneboxes[700]!.id, 42);
    expect(data.oneboxes[700]!.topicId, 700);
  });

  test('private omission remains unknown and synthetic invitees lack IDs', () {
    final full = PostEvent.decode(eventJson())!;
    expect(full.sampleInvitees.single.id, isNull);
    expect(full.sampleInvitees.single.status, isNull);
    final hidden = eventJson()
      ..remove('stats')
      ..remove('sample_invitees')
      ..remove('raw_invitees');
    hidden['should_display_invitees'] = false;
    final event = PostEvent.decode(hidden)!;
    expect(event.stats, isNull);
    expect(event.displayInvitees, isFalse);
    expect(event.watching, isNull);
    expect(event.sampleInvitees, isEmpty);
  });

  test(
    'frozen snapshots preserve unknown values and have structural equality',
    () {
      final json = eventJson(
        overrides: {
          'future_field': {
            'list': [1, 'a'],
          },
        },
      );
      final event = PostEvent.decode(json)!;
      expect(
        event,
        PostEvent.decode(
          eventJson(
            overrides: {
              'future_field': {
                'list': [1, 'a'],
              },
            },
          ),
        ),
      );
      json['name'] = 'changed';
      (json['future_field'] as Map<String, List<Object>>)['list'] = <Object>[];
      expect(event.title, 'Engineering Managers Call');
      expect((event.fields['future_field'] as Map)['list'], [1, 'a']);
      expect(
        () => (event.fields['future_field'] as Map<String, Object?>)['list'] =
            <Object?>[],
        throwsUnsupportedError,
      );
    },
  );

  test(
    'attendance authority is independent of organizer status and capacity',
    () {
      expect(
        PostEvent.decode(
          eventJson(overrides: {'can_update_attendance': false}),
        )!.canRespond,
        isFalse,
      );
      expect(
        PostEvent.decode(
          eventJson(overrides: {'is_standalone': true}),
        )!.canRespond,
        isFalse,
      );
      for (final key in ['is_closed', 'is_expired']) {
        expect(
          PostEvent.decode(eventJson(overrides: {key: true}))!.canRespond,
          isFalse,
        );
      }
      final full = PostEvent.decode(
        eventJson(overrides: {'at_capacity': true}),
      )!;
      expect(full.canChoose('going'), isFalse);
      expect(full.canChoose('interested'), isTrue);
      expect(
        PostEvent.decode(
          eventJson(
            overrides: {'at_capacity': true, 'watching_invitee': watching()},
          ),
        )!.canChoose('going'),
        isTrue,
      );
    },
  );

  test('list and exhausted series tolerate missing details and dates', () {
    final event = PostEvent.decode({
      'id': 42,
      'starts_at': null,
      'ends_at': null,
    })!;
    expect(event.canRespond, isFalse);
    expect(event.canManage, isFalse);
    expect(event.startsAt, isNull);
    expect(event.stats, isNull);
    expect(EventTopicData.decode({'event_ends_at': '2026-09-08'}), isNull);
  });

  test('settings and user permission roundtrip in their own namespace', () {
    final settings = EventSettings.decode(const {
      'discourse_events_enabled': true,
      'discourse_post_event_enabled': true,
      'event_participation_buttons': 'interested|not going',
      'discourse_post_event_allowed_custom_fields': 'dress-code|cost',
    });
    expect(settings.buttons, ['interested', 'not_going']);
    expect(() => settings.buttons[0] = 'going', throwsUnsupportedError);
    const codec = EventSettingsCodec();
    expect(codec.decode(codec.encode(settings)), settings);
    expect(EventUserPermissions.decode({}), isNull);
    expect(
      EventUserPermissions.decode({
        'can_create_discourse_post_event': true,
      })!.canCreate,
      isTrue,
    );
  });
}
