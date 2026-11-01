import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'user_notes_data.dart';

abstract interface class UserNotesApi {
  Future<UserNotesList> list({
    required String siteUrl,
    required int userId,
    required PluginRequestCredentials credentials,
  });
  Future<UserNote> create({
    required String siteUrl,
    required int userId,
    required String raw,
    int? postId,
    int? reviewableId,
    required PluginRequestCredentials credentials,
  });
  Future<void> remove({
    required String siteUrl,
    required int userId,
    required String noteId,
    required PluginRequestCredentials credentials,
  });
}

final class UserNotesApiClient implements UserNotesApi {
  const UserNotesApiClient(this.transport);
  final PluginApiTransport transport;
  @override
  Future<UserNotesList> list({
    required String siteUrl,
    required int userId,
    required PluginRequestCredentials credentials,
  }) async {
    _subject(userId);
    final body = await transport.pluginGetJson(
      siteUrl: siteUrl,
      path: Uri(
        path: '/user_notes',
        queryParameters: {'user_id': '$userId'},
      ).toString(),
      apiKey: credentials.apiKey,
      clientId: credentials.clientId,
    );
    final rows = body['user_notes'], extras = body['extras'];
    if (rows is! List ||
        extras is! Map ||
        extras['username'] is! String ||
        (extras['username'] as String).isEmpty) {
      throw const FormatException('Invalid user notes response');
    }
    final notes = <UserNote>[], ids = <String>{};
    for (final row in rows) {
      if (row is! Map<String, dynamic>) {
        throw const FormatException('Invalid user note record');
      }
      final note = UserNote.read(row, userId: userId);
      if (!ids.add(note.id)) throw const FormatException('Duplicate user note');
      notes.add(note);
    }
    return UserNotesList(username: extras['username'] as String, notes: notes);
  }

  @override
  Future<UserNote> create({
    required String siteUrl,
    required int userId,
    required String raw,
    int? postId,
    int? reviewableId,
    required PluginRequestCredentials credentials,
  }) async {
    _subject(userId);
    final key = credentials.apiKey;
    if (key == null) throw const WriteException(WriteFailure.forbidden);
    if (postId != null && postId <= 0) {
      throw ArgumentError.value(postId, 'postId');
    }
    if (reviewableId != null && reviewableId <= 0) {
      throw ArgumentError.value(reviewableId, 'reviewableId');
    }
    final body = await transport.pluginWriteJson(
      siteUrl: siteUrl,
      path: '/user_notes',
      method: 'POST',
      apiKey: key,
      clientId: credentials.clientId,
      body: {
        'user_note': {
          'user_id': userId,
          'raw': raw,
          'post_id': ?postId,
          'reviewable_id': ?reviewableId,
        },
      },
    );
    final value = body['user_note'];
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid created note');
    }
    return UserNote.read(value, userId: userId);
  }

  @override
  Future<void> remove({
    required String siteUrl,
    required int userId,
    required String noteId,
    required PluginRequestCredentials credentials,
  }) async {
    _subject(userId);
    final key = credentials.apiKey;
    if (key == null) throw const WriteException(WriteFailure.forbidden);
    if (noteId.isEmpty) throw ArgumentError.value(noteId, 'noteId');
    final body = await transport.pluginWriteJson(
      siteUrl: siteUrl,
      path: '/user_notes/${Uri.encodeComponent(noteId)}?user_id=$userId',
      method: 'DELETE',
      apiKey: key,
      clientId: credentials.clientId,
      body: const {},
    );
    if (body['success'] != 'OK') {
      throw const FormatException('Invalid removal response');
    }
  }

  static void _subject(int value) {
    if (value == 0) throw ArgumentError.value(value, 'id');
  }
}
