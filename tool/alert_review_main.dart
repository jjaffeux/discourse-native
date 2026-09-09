// Local-data fixture mounting production adapters; no account or external network IO.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/group.dart';
import 'package:discourse_native/src/plugins/gifs/gif.dart';
import 'package:discourse_native/src/plugins/gifs/gif_picker.dart';
import 'package:discourse_native/src/plugins/gifs/gif_picker_controller.dart';
import 'package:discourse_native/src/shell/composer_tag_removal_notice.dart';
import 'package:discourse_native/src/shell/groups_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/fakes.dart';

late final String _imageUrl;
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  _imageUrl = 'http://127.0.0.1:${server.port}/fixture.png';
  server.listen((request) {
    request.response.headers.contentType = ContentType('image', 'png');
    request.response.add(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    unawaited(request.response.close());
  });
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(const _Review());
}

class _Review extends StatefulWidget {
  const _Review();
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool dark = false;
  bool rtl = false;
  bool large = false;
  bool notice = true;
  bool failed = true;
  int retries = 0;
  late final GifPickerController gifs;
  @override
  void initState() {
    super.initState();
    final credentials = FakeApiCredentialReader()
      ..keys['https://fixture.invalid'] = 'local-fixture';
    gifs = GifPickerController(
      siteUrl: 'https://fixture.invalid',
      api: _GifApi(),
      requests: FakePluginRequestHost(credentials: credentials),
      fileDetail: 'tinygif',
    );
    unawaited(
      gifs
          .selectCategory(
            GifCategory(
              title: 'Local',
              imageUrl: _imageUrl,
              searchTerm: 'local',
            ),
          )
          .then((_) => gifs.loadMore()),
    );
  }

  @override
  void dispose() {
    gifs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: dark ? AppTheme.dark : AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: const Text(
            'Alert Integration Review 38df — local production fixtures',
          ),
        ),
        body: Column(
          children: [
            Wrap(
              spacing: 8,
              children: [
                DButton(
                  label: const Text('Styleguide'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ComponentStyleguidePage(),
                    ),
                  ),
                ),
                DButton(
                  label: const Text('Theme'),
                  onPressed: () => setState(() => dark = !dark),
                ),
                DButton(
                  label: const Text('RTL'),
                  onPressed: () => setState(() => rtl = !rtl),
                ),
                DButton(
                  label: const Text('200%'),
                  onPressed: () => setState(() => large = !large),
                ),
                DButton(
                  label: const Text('Reset errors'),
                  onPressed: () => setState(() {
                    notice = true;
                    failed = true;
                  }),
                ),
                Text('Group retries: $retries'),
              ],
            ),
            Expanded(
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
                child: Directionality(
                  textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      const Text(
                        'Actual ComposerTagRemovalNotice; dismiss preserves caller state',
                      ),
                      if (notice)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: ComposerTagRemovalNotice(
                            message:
                                'They aren’t available in Discourse Native App Development and Support.',
                            onDismiss: () => setState(() => notice = false),
                          ),
                        ),
                      const SizedBox(height: 24),
                      const Text(
                        'Actual GroupsPage; retry clears only the local error',
                      ),
                      SizedBox(
                        height: 320,
                        child: GroupsPage(
                          siteUrl: 'https://fixture.invalid',
                          data: GroupsPageData(
                            loaded: true,
                            error: failed
                                ? 'Could not refresh groups. Saved groups remain available.'
                                : null,
                            groups: const [
                              Group(
                                id: 1,
                                name: 'support',
                                fullName: 'Support Team',
                                userCount: 12,
                              ),
                            ],
                          ),
                          onRefresh: () async {
                            setState(() {
                              failed = false;
                              retries++;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Actual GifPicker; local request failure and retry',
                      ),
                      SizedBox(
                        height: 360,
                        child: GifPicker(
                          controller: gifs,
                          siteUrl: 'https://fixture.invalid',
                          onPicked: (_) {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _GifApi extends FakeDiscourseApi {
  @override
  Future<GifSearchPage> searchGifs({
    required String siteUrl,
    required String apiKey,
    required String query,
    required String fileDetail,
    String position = '0',
    String? clientId,
  }) async {
    if (position != '0') {
      throw const SiteLookupException(
        SiteLookupFailure.unreachable,
        'Local GIF page',
      );
    }
    return GifSearchPage(
      results: [
        GifResult(title: 'Local artwork', url: _imageUrl, width: 1, height: 1),
      ],
      nextPosition: 'next',
    );
  }
}
