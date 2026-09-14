import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/shell/avatar_image.dart';
import 'package:discourse_native/src/shell/group_flair.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/media_pipeline.dart';
import 'support/pixel_samples.dart';

void main() {
  Widget subject(GroupFlairBadge flair, {bool dark = false}) => MaterialApp(
    theme: dark ? AppTheme.dark : AppTheme.light,
    home: Scaffold(body: Center(child: flair)),
  );

  for (final dark in [false, true]) {
    testWidgets(
      'icon flair uses site colors in ${dark ? 'dark' : 'light'} mode',
      (tester) async {
        await tester.pumpWidget(
          subject(
            const GroupFlairBadge(
              url: 'star',
              color: '#fff',
              backgroundColor: '0088cc',
            ),
            dark: dark,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byType(GroupFlairBadge)),
          const Size.square(24),
        );
        final icon = tester.widget<DIcon>(find.byType(DIcon));
        expect(icon.icon, DIcons.star);
        expect(icon.color, Colors.white);
        final container = tester.widget<Container>(
          find.descendant(
            of: find.byType(GroupFlairBadge),
            matching: find.byType(Container),
          ),
        );
        expect(
          (container.decoration! as BoxDecoration).color,
          const Color(0xff0088cc),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final groupHeader in [false, true]) {
    testWidgets(
      'AI ${groupHeader ? 'group header' : 'avatar badge'} preserves artwork and forum surround',
      (tester) async {
        const key = ValueKey('ai-flair');
        for (final theme in [AppTheme.light, AppTheme.dark]) {
          for (final background in <String?>[null, '0088cc']) {
            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: Center(
                  child: RepaintBoundary(
                    key: key,
                    child: groupHeader
                        ? GroupFlair(
                            siteUrl: 'https://meta.example',
                            group: Group(
                              id: 12,
                              name: 'discourse_ai_users',
                              flairIcon: 'discourse-ai',
                              flairColor: 'ff0000',
                              flairBackgroundColor: background,
                            ),
                            size: 38,
                          )
                        : GroupFlairBadge(
                            url: 'discourse-ai',
                            color: 'ff0000',
                            backgroundColor: background,
                            size: 18,
                            iconSize: 18,
                            borderRadius: background == null ? 0 : 9,
                          ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            final origin = tester.getTopLeft(find.byKey(key));
            final icon = tester.getRect(find.byType(SvgPicture)).shift(-origin);
            final colors = await samplePixels(tester, find.byKey(key), [
              icon.topLeft + Offset(icon.width / 2, icon.height * 100 / 512),
              icon.topLeft +
                  Offset(icon.width * 344 / 512, icon.height * 176 / 512),
              Offset((groupHeader ? 38 : 18) / 2, 0.5),
            ]);
            expect(colors, [
              const Color(0xFF333333),
              Colors.white,
              background == null ? Colors.transparent : const Color(0xFF0088CC),
            ]);
            expect(tester.takeException(), isNull);
          }
        }
      },
    );
  }

  testWidgets('unknown icons and invalid colors have a visible fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(
        const GroupFlairBadge(
          url: 'unbundled-custom-icon',
          color: '-fffff',
          backgroundColor: 'invalid',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final icon = tester.widget<DIcon>(find.byType(DIcon));
    expect(icon.icon, DIcons.users);
    expect(icon.color, AppTheme.light.colorScheme.onSurfaceVariant);
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(GroupFlairBadge),
        matching: find.byType(Container),
      ),
    );
    expect((container.decoration! as BoxDecoration).color, Colors.transparent);
    expect(tester.takeException(), isNull);
  });

  testWidgets('background-only flair does not invent an icon', (tester) async {
    await tester.pumpWidget(
      subject(const GroupFlairBadge(url: null, backgroundColor: 'abc')),
    );
    expect(find.byType(DIcon), findsNothing);
    final container = tester.widget<Container>(
      find.descendant(
        of: find.byType(GroupFlairBadge),
        matching: find.byType(Container),
      ),
    );
    expect(
      (container.decoration! as BoxDecoration).color,
      const Color(0xffaabbcc),
    );
  });

  testWidgets(
    'image flair uses the shared loader and contains the entire image',
    (tester) async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response(
          '<svg xmlns="http://www.w3.org/2000/svg" width="30" height="10"><rect width="30" height="10" fill="red"/></svg>',
          200,
          headers: {'content-type': 'image/svg+xml'},
        );
      });
      installTestMediaPipeline(client: client);
      addTearDown(client.close);
      await tester.pumpWidget(
        subject(const GroupFlairBadge(url: 'https://meta.example/flair.png')),
      );
      await tester.pumpAndSettle();
      expect(requests, 1);
      expect(
        tester.widget<AvatarImage>(find.byType(AvatarImage)).fit,
        BoxFit.contain,
      );
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byType(DIcon), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unavailable images keep a group marker without throwing', (
    tester,
  ) async {
    final client = MockClient((_) async => http.Response('', 404));
    installTestMediaPipeline(client: client);
    addTearDown(client.close);
    await tester.pumpWidget(
      subject(const GroupFlairBadge(url: 'https://meta.example/missing.png')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<DIcon>(find.byType(DIcon)).icon, DIcons.users);
    expect(tester.takeException(), isNull);
  });
}
