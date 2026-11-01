import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_plugin_test.dart';
import 'package:discourse_native/src/plugins/user_notes/user_notes_api.dart';
import 'package:discourse_native/src/plugins/user_notes/user_notes_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'user_notes_fixture.dart';

const _credentials = PluginRequestCredentials(
  apiKey: 'staff-key',
  clientId: 'client',
);
void main() {
  test(
    'exact list/create/delete routes and serializer envelopes remain plugin-owned',
    () async {
      final transport = RecordingPluginTransport(
        responses: {
          'GET /user_notes?user_id=7': notesPage([
            noteWire(
              postId: '12',
              postUrl: '/community/t/topic/9/2',
              reviewableId: '33',
            ),
          ]),
          'POST /user_notes': {'user_note': noteWire(id: 'created')},
          'DELETE /user_notes/a%2Fb?user_id=7': {'success': 'OK'},
        },
      );
      final api = UserNotesApiClient(transport);
      final result = await api.list(
        siteUrl: notesSite,
        userId: 7,
        credentials: _credentials,
      );
      expect(result.notes.single.author!.id, -1);
      expect(result.notes.single.post!.id, 12);
      expect(result.notes.single.reviewableId, 33);
      expect(result.notes.single.post!.url, '/community/t/topic/9/2');
      await api.create(
        siteUrl: notesSite,
        userId: 7,
        raw: 'Some context',
        postId: 12,
        credentials: _credentials,
      );
      await api.remove(
        siteUrl: notesSite,
        userId: 7,
        noteId: 'a/b',
        credentials: _credentials,
      );
      expect(transport.writes.first.body, {
        'user_note': {'user_id': 7, 'raw': 'Some context', 'post_id': 12},
      });
      expect(
        transport.requests.every(
          (r) =>
              r.siteUrl == notesSite &&
              r.apiKey == 'staff-key' &&
              r.clientId == 'client',
        ),
        isTrue,
      );
    },
  );
  test(
    'redacted post association stays absent and missing delete permission fails closed',
    () {
      final wire = noteWire(postId: '9')..remove('can_delete');
      final note = UserNote.read(wire, userId: 7);
      expect(note.post, isNull);
      expect(note.canDelete, isFalse);
      expect(UserNote.read(noteWire(userId: -1), userId: -1).userId, -1);
    },
  );
  test(
    'malformed and foreign-subject records cannot create a valid list',
    () async {
      for (final invalid in [
        noteWire(userId: 8),
        noteWire()..['created_at'] = 'invalid',
        noteWire()..['id'] = 5,
      ]) {
        final api = UserNotesApiClient(
          RecordingPluginTransport(
            responses: {
              'GET /user_notes?user_id=7': notesPage([invalid]),
            },
          ),
        );
        await expectLater(
          api.list(siteUrl: notesSite, userId: 7, credentials: _credentials),
          throwsFormatException,
        );
      }
    },
  );
  test('unrooted create records and duplicate list IDs are rejected', () async {
    final api = UserNotesApiClient(
      RecordingPluginTransport(
        responses: {
          'POST /user_notes': noteWire(),
          'GET /user_notes?user_id=7': notesPage([noteWire(), noteWire()]),
        },
      ),
    );
    await expectLater(
      api.create(
        siteUrl: notesSite,
        userId: 7,
        raw: 'note',
        credentials: _credentials,
      ),
      throwsFormatException,
    );
    await expectLater(
      api.list(siteUrl: notesSite, userId: 7, credentials: _credentials),
      throwsFormatException,
    );
  });
  test(
    'count presence differs from zero and settings persistence contains no private values',
    () {
      expect(UserNotesCount.read(const {}), isNull);
      expect(
        UserNotesCount.read({
          'custom_fields': {'user_notes_count': '0'},
        })!.value,
        0,
      );
      expect(
        UserNotesCount.read({
          'user_custom_fields': {'user_notes_count': 3},
        }, post: true)!.value,
        3,
      );
      expect(UserNotesCount.read({'user_notes_count': -1}), isNull);
      const codec = UserNotesSettingsCodec();
      expect(
        codec.encode(
          const UserNotesSettings(
            enabled: true,
            placement: UserNotesPlacement.avatar,
          ),
        ),
        {'user_notes_enabled': true, 'user_notes_icon_placement': 'avatar'},
      );
      expect(UserNotesSettings.read(const {}).enabled, isFalse);
    },
  );
}
