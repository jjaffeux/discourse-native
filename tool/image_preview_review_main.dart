import 'dart:io';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_uploads.dart';
import 'package:discourse_native/src/shell/cooked_html.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bytes = await rootBundle.load(
    'packages/discourse_native/src/styleguide/assets/discourse.png',
  );
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.headers.contentType = ContentType('image', 'png');
    request.response.add(bytes.buffer.asUint8List());
    await request.response.close();
  });
  runApp(_Review(site: 'http://127.0.0.1:${server.port}'));
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
}

class _Review extends StatefulWidget {
  const _Review({required this.site});
  final String site;

  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  bool dark = false, narrow = false, rtl = false, large = false, custom = false;

  @override
  Widget build(BuildContext context) => DFocusHighlight(
    child: MaterialApp(
      theme: custom
          ? StyleguideTheme.forest.resolve(AppTheme.light)
          : dark
          ? AppTheme.dark
          : AppTheme.light,
      home: Scaffold(
        body: SafeArea(
          child: Builder(
            builder: (context) => Column(
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    DButton(
                      label: const Text('Light / dark'),
                      onPressed: () => setState(() => dark = !dark),
                    ),
                    DButton(
                      label: const Text('Custom palette'),
                      onPressed: () => setState(() => custom = !custom),
                    ),
                    DButton(
                      label: const Text('Narrow'),
                      onPressed: () => setState(() => narrow = !narrow),
                    ),
                    DButton(
                      label: const Text('RTL'),
                      onPressed: () => setState(() => rtl = !rtl),
                    ),
                    DButton(
                      label: const Text('Large text'),
                      onPressed: () => setState(() => large = !large),
                    ),
                    DButton(
                      label: const Text('Styleguide'),
                      onPressed: () => showComponentStyleguide(context),
                    ),
                  ],
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Center(
                      child: SizedBox(
                        width: narrow ? 300 : 720,
                        child: MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            textScaler: TextScaler.linear(large ? 2 : 1),
                          ),
                          child: Directionality(
                            textDirection: rtl
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Post image'),
                                  CookedHtml(
                                    siteUrl: widget.site,
                                    html:
                                        '''
<div class="lightbox-wrapper"><a class="lightbox" href="${widget.site}/post.png" title="community-gathering.png"><img src="${widget.site}/post.png" width="480" height="240" alt="Community gathering"><div class="meta"><span class="informations">1024×512 128 KB</span></div></a></div>
''',
                                  ),
                                  const SizedBox(height: 20),
                                  const Text(
                                    'Chat images (second image exercises GIF controls)',
                                  ),
                                  ChatUploads(
                                    siteUrl: widget.site,
                                    uploads: const [
                                      ChatUpload(
                                        url: '/chat.png',
                                        originalFilename:
                                            'community-gathering.png',
                                        kind: ChatUploadKind.image,
                                        width: 480,
                                        height: 240,
                                        humanFilesize: '128 KB',
                                      ),
                                      ChatUpload(
                                        url: '/animated.gif',
                                        originalFilename: 'animated.gif',
                                        kind: ChatUploadKind.image,
                                        width: 480,
                                        height: 240,
                                        humanFilesize: '128 KB',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
