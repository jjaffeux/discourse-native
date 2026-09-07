import 'package:discourse_native/src/data/avatar_loader.dart';
import 'package:discourse_native/src/models/json.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _site = 'https://forum.example/community';
const _uploaded = '/community/user_avatar/forum.example/sam/{size}/1.png';
const _letter = '/community/letter_avatar/sam/{size}/1.png';

void main() {
  group('resolveAvatarUrl', () {
    for (final template in [_uploaded, _letter]) {
      for (final site in [_site, '$_site/']) {
        test('resolves $template against the origin of $site', () {
          expect(
            resolveAvatarUrl(template, site),
            'https://forum.example${template.replaceAll('{size}', '90')}',
          );
        });
      }
    }

    test('a root path need not start with the forum directory', () {
      expect(
        resolveAvatarUrl('/letter_avatar/sam/{size}/1.png', _site),
        'https://forum.example/letter_avatar/sam/90/1.png',
      );
    });

    test('keeps relative paths under the whole forum directory', () {
      for (final site in ['$_site/nested', '$_site/nested/']) {
        expect(
          resolveAvatarUrl('user_avatar/sam/{size}/1.png', site),
          '$_site/nested/user_avatar/sam/90/1.png',
        );
      }
    });

    test('resolves both path forms on root forums', () {
      for (final site in ['https://forum.example', 'https://forum.example/']) {
        for (final prefix in ['', '/']) {
          expect(
            resolveAvatarUrl('${prefix}user_avatar/sam/{size}/1.png', site),
            'https://forum.example/user_avatar/sam/90/1.png',
          );
        }
      }
    });

    test('preserves ports, IPv6 hosts, and the forum protocol', () {
      for (final origin in [
        'https://forum.example:8443',
        'http://localhost:3000',
        'http://[::1]:3000',
      ]) {
        expect(
          resolveAvatarUrl(_uploaded, '$origin/community'),
          '$origin/community/user_avatar/forum.example/sam/90/1.png',
        );
      }
    });

    test('preserves encoded paths, queries, and fragments', () {
      const site = 'https://forum.example:8443/team%20space';
      const path = 'user_avatar/sam%2Bdev/{size}/a%2Fb.png?v=a%2Bb#part%20one';
      const expected =
          '$site/user_avatar/sam%2Bdev/90/a%2Fb.png'
          '?v=a%2Bb#part%20one';
      expect(resolveAvatarUrl('/team%20space/$path', site), expected);
      expect(resolveAvatarUrl(path, site), expected);
    });

    test('replaces every size placeholder and accepts fixed images', () {
      expect(
        resolveAvatarUrl(
          '/community/{size}/avatar.png?size={size}',
          _site,
          size: 240,
        ),
        '$_site/240/avatar.png?size=240',
      );
      expect(
        resolveAvatarUrl('/community/avatar.png', _site),
        '$_site/avatar.png',
      );
    });

    test('preserves absolute CDN URLs without consulting the forum URL', () {
      for (final origin in [
        'https://cdn.example:8443',
        'http://cdn.example:8080',
      ]) {
        expect(
          resolveAvatarUrl(
            '$origin/sam%2Bdev/{size}.png?v=1',
            'https://[bad',
            size: 48,
          ),
          '$origin/sam%2Bdev/48.png?v=1',
        );
      }
    });

    test('continues to use HTTPS for protocol-relative CDN URLs', () {
      expect(
        resolveAvatarUrl(
          '//cdn.example:8443/sam/{size}.png',
          'http://localhost:3000/community',
        ),
        'https://cdn.example:8443/sam/90.png',
      );
    });

    test('missing templates stay null even with a malformed forum URL', () {
      expect(resolveAvatarUrl(null, 'https://[bad'), isNull);
      expect(resolveAvatarUrl('', 'https://[bad'), isNull);
    });

    test('malformed forum URLs retain the non-throwing fallback', () {
      for (final site in [
        '',
        'forum.example/community',
        'https://[bad',
        'https://forum.example:bad/community',
        'https:///community',
      ]) {
        expect(
          resolveAvatarUrl('/avatar/{size}.png', site),
          '$site/avatar/90.png',
        );
      }
    });

    test('odd template text cannot interrupt model parsing', () {
      for (final template in [
        '/community/bad%escape/{size}.png',
        '/community/[avatar]/{size}.png',
        '/community/avatar with spaces/{size}.png',
        '//[bad/{size}.png',
        'https://[bad/{size}.png',
        ' ',
      ]) {
        expect(() => resolveAvatarUrl(template, _site), returnsNormally);
        expect(
          () => Post.fromJson({'avatar_template': template}, _site),
          returnsNormally,
        );
      }
    });

    test('does not promote other schemes to absolute network URLs', () {
      for (final template in [
        'ftp://cdn.example/{size}.png',
        'file:///avatars/{size}.png',
        'data:image/png;base64,AA==',
        'javascript:avatar()',
      ]) {
        expect(
          resolveAvatarUrl(template, _site),
          '$_site/${template.replaceAll('{size}', '90')}',
        );
      }
    });
  });

  group('subfolder avatar decoding', () {
    for (final template in [_uploaded, _letter]) {
      final user = <String, dynamic>{
        'id': 7,
        'username': 'sam',
        'avatar_template': template,
      };
      final expected =
          'https://forum.example${template.replaceAll('{size}', '90')}';

      test('Post decodes $template', () {
        final post = Post.fromJson({
          'id': 42,
          'post_number': 1,
          'username': 'sam',
          'avatar_template': template,
          'cooked': '<p>Hello</p>',
        }, _site);
        expect(post.avatarUrl, expected);
      });

      test('ChatMessage decodes its nested author with $template', () {
        final message = ChatMessage.fromJson({
          'id': 42,
          'chat_channel_id': 9,
          'cooked': '<p>Hello</p>',
          'user': user,
        }, _site);
        expect(message.author.avatarUrl, expected);
      });

      test('UserCard decodes $template at its larger size', () {
        final card = UserCard.fromJson(user, _site);
        expect(
          card.avatarUrl,
          'https://forum.example${template.replaceAll('{size}', '240')}',
        );
      });
    }
  });

  group('decoded avatar loading', () {
    test(
      'requests the server path once without doubling the subfolder',
      () async {
        final requested = <Uri>[];
        final client = MockClient((request) async {
          requested.add(request.url);
          return http.Response(
            '<svg></svg>',
            200,
            headers: {'content-type': 'image/svg+xml'},
          );
        });
        addTearDown(client.close);
        final loader = AvatarLoader(client: client);
        addTearDown(loader.close);
        final post = Post.fromJson(const {'avatar_template': _uploaded}, _site);

        expect(await loader.load(post.avatarUrl!), isNotNull);
        expect(requested, [
          Uri.parse('$_site/user_avatar/forum.example/sam/90/1.png'),
        ]);
      },
    );

    test('transport still rejects credentials and unsafe schemes', () async {
      final requested = <Uri>[];
      final client = MockClient((request) async {
        requested.add(request.url);
        return http.Response('<svg></svg>', 200);
      });
      addTearDown(client.close);
      final loader = AvatarLoader(client: client);
      addTearDown(loader.close);

      for (final (template, site) in [
        (_uploaded, 'https://user:pass@forum.example/community'),
        (_uploaded, 'ftp://forum.example/community'),
        (_uploaded, 'http://forum.example/community'),
        ('https://user:pass@cdn.example/{size}.png', _site),
        ('//user:pass@cdn.example/{size}.png', _site),
        ('httpx://cdn.example/{size}.png', _site),
      ]) {
        expect(await loader.load(resolveAvatarUrl(template, site)!), isNull);
      }
      expect(requested, isEmpty);
    });
  });
}
