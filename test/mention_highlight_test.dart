import 'package:discourse_native/src/data/site_appearance_parser.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/shell/pill.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

import 'support/fakes.dart';

const _sourceSite = 'https://source.example.com';
const _selectedSite = 'https://selected.example.com';
const _mentions = '''
<p>Hello <a class="mention" href="/u/mArTiN">@mArTiN</a>
and <a class="mention" href="/u/sam">@sam</a>.</p>
''';

Future<ShellController> _pumpMentions(
  WidgetTester tester, {
  String html = _mentions,
  String sourceSite = _sourceSite,
  String? username = 'Martin',
  ThemeData? theme,
}) async {
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      DiscourseInstance(
        url: sourceSite,
        title: 'Source',
        user: username == null ? null : DiscourseUser(username: username),
      ),
      const DiscourseInstance(
        url: _selectedSite,
        title: 'Selected',
        user: DiscourseUser(username: 'sam'),
      ),
    ]),
    api: FakeDiscourseApi(user: const DiscourseUser(username: 'sam')),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  addTearDown(controller.dispose);
  await controller.load();
  await tester.pumpWidget(
    ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: theme ?? AppTheme.dark,
        home: Scaffold(
          body: CookedHtml(html: html, siteUrl: sourceSite),
        ),
      ),
    ),
  );
  await tester.pump();
  return controller;
}

Color? _fill(WidgetTester tester, String label) {
  final container = tester.widget<Container>(
    find.descendant(
      of: find.widgetWithText(Pill, label),
      matching: find.byType(Container),
    ),
  );
  return (container.decoration! as BoxDecoration).color;
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('own mentions use the $brightness highlight', (tester) async {
      final theme = brightness == Brightness.dark
          ? AppTheme.dark
          : AppTheme.light;
      await _pumpMentions(tester, theme: theme);

      expect(_fill(tester, '@mArTiN'), theme.shell.currentUserMention);
      expect(_fill(tester, '@sam'), theme.shell.mention);
      expect(theme.shell.currentUserMention, isNot(theme.shell.mention));
    });
  }

  testWidgets('uses the site tertiary-400 and keeps it when hovered', (
    tester,
  ) async {
    final palette = parseSiteAppearanceStylesheet('''
      :root {
        --scheme-type: light;
        --primary: #222222;
        --secondary: #ffffff;
        --tertiary: #663399;
        --tertiary-400: #ddccee;
        --mention-background-color: #eeeeee;
      }
    ''')!;
    final theme = AppTheme.fromPalette(palette);
    await _pumpMentions(tester, theme: theme);

    expect(_fill(tester, '@mArTiN'), const Color(0xFFDDCCEE));
    expect(_fill(tester, '@sam'), const Color(0xFFEEEEEE));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('@mArTiN')));
    await tester.pump();

    expect(
      _fill(tester, '@mArTiN'),
      Color.alphaBlend(
        theme.colorScheme.onSurface.withValues(alpha: 0.08),
        const Color(0xFFDDCCEE),
      ),
    );

    await mouse.moveTo(const Offset(700, 500));
    await tester.pump();
    expect(_fill(tester, '@mArTiN'), const Color(0xFFDDCCEE));
  });

  testWidgets('matches the profile href, leaving other mentions unchanged', (
    tester,
  ) async {
    await _pumpMentions(
      tester,
      html: '''
        <p><a class="mention" href="/u/martin">@different-label</a></p>
        <p><a class="mention" href="/u/sam">@martin</a></p>
        <p><a class="mention-group" href="/groups/martin">@Martin</a></p>
        <p><a class="mention" href="https://elsewhere.example/u/martin">@MARTIN</a></p>
        <p><a class="mention" href="/u/martin2">@martin2</a></p>
      ''',
    );

    expect(
      _fill(tester, '@different-label'),
      AppTheme.dark.shell.currentUserMention,
    );
    for (final label in ['@martin', '@Martin', '@MARTIN', '@martin2']) {
      expect(_fill(tester, label), AppTheme.dark.shell.mention);
    }
  });

  testWidgets('matches a site subfolder in the profile href', (tester) async {
    await _pumpMentions(
      tester,
      sourceSite: '$_sourceSite/forum',
      html: '''
        <p><a class="mention" href="/forum/u/MARTIN">@MARTIN</a></p>
        <p><a class="mention" href="/u/martin">@martin</a></p>
      ''',
    );

    expect(_fill(tester, '@MARTIN'), AppTheme.dark.shell.currentUserMention);
    expect(_fill(tester, '@martin'), AppTheme.dark.shell.mention);
  });

  testWidgets('keeps using the post source account when switching sites', (
    tester,
  ) async {
    final controller = await _pumpMentions(tester);
    controller.selectInstance(1);
    await tester.pump();

    expect(controller.currentInstance?.url, _selectedSite);
    expect(_fill(tester, '@mArTiN'), AppTheme.dark.shell.currentUserMention);
    expect(_fill(tester, '@sam'), AppTheme.dark.shell.mention);
  });

  testWidgets('updates cached mentions after account replacement and logout', (
    tester,
  ) async {
    final controller = await _pumpMentions(tester);
    final renderer = tester.widget<HtmlWidget>(find.byType(HtmlWidget));
    expect(_fill(tester, '@mArTiN'), AppTheme.dark.shell.currentUserMention);

    await controller.connectCurrentInstance();
    await tester.pump();

    expect(controller.currentInstance?.user?.username, 'sam');
    expect(_fill(tester, '@mArTiN'), AppTheme.dark.shell.mention);
    expect(_fill(tester, '@sam'), AppTheme.dark.shell.currentUserMention);
    expect(tester.widget<HtmlWidget>(find.byType(HtmlWidget)), same(renderer));

    await controller.disconnectCurrentInstance();
    await tester.pump();

    expect(controller.currentInstance?.user, isNull);
    expect(_fill(tester, '@mArTiN'), AppTheme.dark.shell.mention);
    expect(_fill(tester, '@sam'), AppTheme.dark.shell.mention);
  });

  testWidgets('signed-out source posts do not use another site account', (
    tester,
  ) async {
    final controller = await _pumpMentions(tester, username: null);
    controller.selectInstance(1);
    await tester.pump();

    expect(_fill(tester, '@mArTiN'), AppTheme.dark.shell.mention);
    expect(_fill(tester, '@sam'), AppTheme.dark.shell.mention);
  });
}
