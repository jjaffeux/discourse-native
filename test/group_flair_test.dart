import 'package:discourse_native/src/shell/avatar_image.dart';
import 'package:discourse_native/src/shell/group_flair.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/media_pipeline.dart';

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
              url: 'discourse-ai',
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
        expect(icon.icon, DIcons.discourseAi);
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
