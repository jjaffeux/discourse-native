import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/models/list_link.dart';
import 'package:discourse_native/src/models/topic_link.dart';
import 'package:discourse_native/src/plugins/assign/assigned_group_link.dart';
import 'package:discourse_native/src/plugins/discourse_github/oneboxes/pr/inline.dart';
import 'package:discourse_native/src/shell/inline_video.dart';
import 'package:discourse_native/src/shell/mention.dart';
import 'package:discourse_native/src/shell/user_card.dart';
import 'package:discourse_native/src/shell/youtube_video.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;

// These are valid URI escapes whose bytes are not a valid UTF-8 string.
// Uri.tryParse succeeds; decoding pathSegments or queryParameters then fails.
const _malformedUtf8 = [
  '%FF',
  '%C3',
  '%ED%A0%80',
  '%F4%90%80%80',
  '%80',
  '%C0%AF',
];

void main() {
  final readers = <String, bool Function(String)>{
    'topic': (value) => TopicLink.parse('/t/$value/1') == null,
    'category': (value) => ListLink.parse('/c/$value/1') == null,
    'category query': (value) =>
        ListLink.parse('/c/todo/5?assigned=$value') == null,
    'group': (value) => GroupRoute.parse('/g/$value') == null,
    'assigned group': (value) =>
        AssignedGroupLink.parse('/g/$value/assigned') == null,
    'profile': (value) =>
        usernameFromProfileUrl(Uri.parse('/u/$value')) == null,
    'forum membership': (value) => !const DiscourseInstance(
      url: 'https://example.com/forum',
      title: 'Forum',
    ).serves(Uri.parse('https://example.com/forum/t/$value/1')),
    'forum relative path': (value) =>
        DiscourseInstance.pathWithinUrl(
          'https://example.com/forum',
          Uri.parse('/forum/t/$value/1'),
        ) ==
        null,
    'YouTube path': (value) =>
        YoutubeVideoData.tryParseUrl('https://youtu.be/$value') == null,
    'YouTube query': (value) =>
        YoutubeVideoData.tryParseUrl('https://youtube.com/watch?v=$value') ==
        null,
    'GitHub inline onebox': (value) => !GithubPullRequestInlineOnebox.matches(
      dom.Element.tag('a')
        ..attributes['href'] = 'https://github.com/$value/repository/pull/1',
    ),
  };

  for (final entry in readers.entries) {
    test('${entry.key} declines malformed UTF-8', () {
      for (final value in _malformedUtf8) {
        expect(entry.value(value), isTrue, reason: value);
      }
    });
  }

  test(
    'bookmark payloads remain readable when their URL has malformed UTF-8',
    () {
      for (final value in _malformedUtf8) {
        final url = 'https://example.com/t/$value/1';
        final bookmark = Bookmark.fromJson({
          'id': 3,
          'title': 'Saved post',
          'bookmarkable_url': url,
        });
        expect(bookmark.id, 3);
        expect(bookmark.title, 'Saved post');
        expect(bookmark.path, url);
      }
    },
  );

  test('video posters fall back when their filename cannot be decoded', () {
    for (final value in _malformedUtf8) {
      final url = 'https://example.com/$value.mp4';
      final data = InlineVideoData.fromUpload(
        url: url,
        title: '',
        siteUrl: 'https://example.com',
      );
      expect(data?.source.toString(), url);
      expect(data?.title, 'Video');
    }
  });

  test('group mentions remain renderable when their target is malformed', () {
    for (final value in _malformedUtf8) {
      final element = dom.Element.tag('a')
        ..classes.add('mention-group')
        ..attributes['href'] = '/groups/$value'
        ..text = '@staff';
      expect(mentionWidgetBuilder(element, null), isNotNull);
    }
  });
}
