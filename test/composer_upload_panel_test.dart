import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/shell/composer_block_surface.dart';
import 'package:discourse_native/src/shell/composer_clipboard.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_galleries.dart';
import 'package:discourse_native/src/shell/composer_image.dart';
import 'package:discourse_native/src/shell/composer_image_gallery.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/composer_upload_picker.dart';
import 'package:discourse_native/src/shell/markdown_editing_controller.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart'
    as images;

import 'support/fakes.dart';

void main() {
  group('upload lifecycle', () {
    for (final staff in [false, true]) {
      testWidgets('toolbar uploads allowed files (staff: $staff)', (
        tester,
      ) async {
        const config = SiteConfig(
          authorizedExtensions: [
            'png',
            'pdf',
            'mp4',
            'mp3',
            'tar.gz',
            'custom',
          ],
          authorizedExtensionsForStaff: ['zip'],
        );
        final uploaded = <String>[];
        final composer = ComposerController(
          _target,
          canUploadImage: (name) => config.canUploadImage(name, staff: staff),
          canUploadFile: (name) => config.canUploadFile(name, staff: staff),
          imageUploader:
              (file, {required onProgress, required abortTrigger}) async {
                uploaded.add(file.name);
                return ComposerUploadResult(
                  id: uploaded.length,
                  originalFilename: file.name,
                  shortUrl: 'upload://${file.name}',
                  url: 'https://meta.discourse.org/uploads/${file.name}',
                );
              },
        );
        final shell = await _shell();
        addTearDown(shell.dispose);
        addTearDown(composer.dispose);
        await _pumpPanel(
          tester,
          shell,
          composer,
          pickFiles: () async => [
            for (final name in [
              'photo.png',
              'notes.pdf',
              'video.mp4',
              'audio.mp3',
              'archive.tar.gz',
              'data.custom',
              'staff.zip',
              'blocked.exe',
            ])
              ComposerUploadFile(
                name: name,
                length: _file.length,
                openRead: _file.openRead,
              ),
          ],
        );

        final button = tester.widget<DButton>(
          find.byKey(const ValueKey('composer-upload')),
        );
        expect(button.tooltip, 'Upload');
        expect((button.icon! as DIcon).icon, DIcons.paperclip);
        await tester.tap(find.byKey(const ValueKey('composer-upload')));
        await tester.pumpAndSettle();
        expect(find.text('Photo Library'), findsOneWidget);
        expect(find.text('Files'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('composer-upload-files')));
        await tester.pumpAndSettle();

        expect(uploaded, [
          'photo.png',
          'notes.pdf',
          'video.mp4',
          'audio.mp3',
          'archive.tar.gz',
          'data.custom',
          if (staff) 'staff.zip',
        ]);
        expect(composer.text.text, contains('![photo](upload://photo.png)'));
        for (final name in uploaded.skip(1)) {
          expect(
            composer.text.text,
            contains(switch (name) {
              'video.mp4' => '![video|video](upload://video.mp4)',
              'audio.mp3' => '![audio|audio](upload://audio.mp3)',
              _ => '[$name](upload://$name)',
            }),
          );
        }
        expect(composer.text.imageBlocks.single.url, 'upload://photo.png');
        expect(composer.text.text, isNot(contains('blocked.exe')));
        expect(composer.notice, contains('not allowed'));
      });
    }

    for (final ontoGallery in [false, true]) {
      testWidgets(
        'video drops insert playable video markdown (gallery: $ontoGallery)',
        (tester) async {
          final files = <String>[];
          const config = SiteConfig(authorizedExtensions: ['png', 'mp4']);
          final composer = ComposerController(
            _target,
            canUploadImage: (name) => config.canUploadImage(name, staff: false),
            canUploadFile: (name) => config.canUploadFile(name, staff: false),
            imageUploader:
                (file, {required onProgress, required abortTrigger}) async {
                  files.add(file.name);
                  return const ComposerUploadResult(
                    id: 73,
                    originalFilename: 'screen.mp4',
                    shortUrl: 'upload://screen.mp4',
                    url: 'https://meta.discourse.org/uploads/screen.mp4',
                    width: 1920,
                    height: 1080,
                  );
                },
          );
          const gallery =
              '[grid]\n![one](upload://one)\n![two](upload://two)\n[/grid]\n';
          if (ontoGallery) composer.text.text = gallery;
          final shell = await _shell();
          addTearDown(shell.dispose);
          addTearDown(composer.dispose);
          await _pumpPanel(tester, shell, composer);
          await tester.pumpAndSettle();
          final position = tester.getCenter(
            ontoGallery
                ? find.byType(ComposerImageGalleryControl)
                : find.byType(ComposerEditor),
          );
          final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
          dropTarget.onDragEntered!(
            DropEventDetails(localPosition: position, globalPosition: position),
          );
          await tester.pump();
          dropTarget.onDragDone!(
            DropDoneDetails(
              files: [
                DropItemFile(
                  '/tmp/screen.mp4',
                  bytes: Uint8List.fromList([1, 2, 3]),
                ),
              ],
              localPosition: position,
              globalPosition: position,
            ),
          );
          await tester.pumpAndSettle();
          expect(files, ['screen.mp4']);
          expect(composer.notice, isNull);
          expect(
            composer.text.text,
            '${ontoGallery ? gallery : ''}![screen|video](upload://screen.mp4)\n',
          );
          expect(composer.text.imageBlocks, hasLength(ontoGallery ? 2 : 0));
          if (ontoGallery) {
            expect(composer.text.galleryBlocks.single.images, hasLength(2));
          }
        },
      );
    }

    testWidgets('native clipboard images become retryable PNG uploads', (
      tester,
    ) async {
      const channel = MethodChannel('pasteboard');
      final messenger = tester.binding.defaultBinaryMessenger;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return switch (call.method) {
          'files' => const <String>[],
          'image' => Uint8List.fromList(const [1, 2, 3]),
          _ => fail('Unexpected pasteboard method: ${call.method}'),
        };
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      // A screenshot copied to the clipboard publishes pixels and no text.
      final textCalls = _mockClipboardText(tester, null);

      final files = await readComposerClipboardFiles();

      expect(files, hasLength(1));
      expect(files.single.name, 'pasted-image.png');
      expect(await files.single.length(), 3);
      expect(await files.single.openRead().expand((chunk) => chunk).toList(), [
        1,
        2,
        3,
      ]);
      expect(await files.single.openRead().expand((chunk) => chunk).toList(), [
        1,
        2,
        3,
      ]);
      expect(calls, ['files', 'image']);
      expect(textCalls, ['Clipboard.hasStrings']);
    });

    testWidgets(
      'text copied beside an image flavour pastes as text, never the pixels',
      (tester) async {
        // Excel, Numbers and Word publish PDF or TIFF renderings of the copied
        // cells next to their text, and the plugin reads either as an image.
        const copied = 'Q3 revenue 1200';
        final pluginCalls = _mockPasteboardPlugin(
          tester,
          files: const [],
          image: Uint8List.fromList(const [80, 78, 71]),
        );
        final fileUrlCalls = _mockPasteboardFileUrls(tester, const []);
        final textCalls = _mockClipboardText(tester, copied);
        const config = SiteConfig(authorizedExtensions: ['*']);
        final uploaded = <String>[];
        final composer = ComposerController(
          _target,
          canUploadImage: (name) => config.canUploadImage(name, staff: false),
          canUploadFile: (name) => config.canUploadFile(name, staff: false),
          imageUploader:
              (file, {required onProgress, required abortTrigger}) async {
                uploaded.add(file.name);
                throw StateError('Copied text must not upload its rendering');
              },
        );
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        composer.text.value = const TextEditingValue(
          text: 'See ',
          selection: TextSelection.collapsed(offset: 4),
        );
        await _pumpPanel(tester, shell, composer);

        await _pasteShortcut(tester);

        expect(composer.text.text, 'See $copied');
        expect(composer.uploads, isEmpty);
        expect(uploaded, isEmpty);
        expect(composer.notice, isNull);
        expect(pluginCalls, isNot(contains('image')));
        expect(fileUrlCalls, ['fileURLPaths']);
        expect(textCalls.first, 'Clipboard.hasStrings');
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    for (final name in ['copied screenshot.png', 'copied video.mp4']) {
      testWidgets(
        'clipboard file $name uses the original contents instead of the file icon',
        (tester) async {
          final directory = Directory.systemTemp.createTempSync(
            'discourse-native-clipboard-',
          );
          addTearDown(() => directory.deleteSync(recursive: true));
          final copiedFile = File('${directory.path}/$name');
          copiedFile.writeAsBytesSync(const [4, 5, 6, 7]);

          const channel = MethodChannel('pasteboard');
          final messenger = tester.binding.defaultBinaryMessenger;
          final calls = <String>[];
          messenger.setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            return switch (call.method) {
              'files' => <String>[copiedFile.path],
              'image' => Uint8List.fromList(const [80, 78, 71]),
              _ => fail('Unexpected pasteboard method: ${call.method}'),
            };
          });
          addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
          // Finder also publishes the copied file's name as plain text.
          final textCalls = _mockClipboardText(tester, name);

          final files = (await tester.runAsync(readComposerClipboardFiles))!;

          expect(files, hasLength(1));
          expect(files.single.name, name);
          final upload = await tester.runAsync(
            () async => (
              await files.single.length(),
              await files.single.openRead().expand((chunk) => chunk).toList(),
            ),
          );
          expect(upload?.$1, 4);
          expect(upload?.$2, [4, 5, 6, 7]);
          expect(calls, ['files']);
          expect(textCalls, isEmpty);
        },
      );
    }

    testWidgets('macOS reads copied files only through the file-URL channel', (
      tester,
    ) async {
      final directory = Directory.systemTemp.createTempSync(
        'discourse-native-clipboard-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final copiedFile = File('${directory.path}/copied.pdf')
        ..writeAsBytesSync(const [4, 5, 6]);
      final pluginCalls = _mockPasteboardPlugin(tester, files: const []);
      final fileUrlCalls = _mockPasteboardFileUrls(tester, [copiedFile.path]);

      final files = await tester.runAsync(readComposerClipboardFiles);

      expect(files!.single.name, 'copied.pdf');
      expect(await tester.runAsync(files.single.length), 3);
      expect(fileUrlCalls, ['fileURLPaths']);
      expect(pluginCalls, isEmpty);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets(
      'clipboard paths that are not regular files are never uploaded',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync(
          'discourse-native-clipboard-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        // Finder also publishes the copied item's icon as an image, so paths
        // which cannot be uploaded must not fall through to the pixel read.
        final pluginCalls = _mockPasteboardPlugin(
          tester,
          files: [directory.path, '${directory.path}/deleted.png'],
          image: Uint8List.fromList(const [80, 78, 71]),
        );

        final files = await tester.runAsync(readComposerClipboardFiles);

        expect(files, isEmpty);
        expect(pluginCalls, ['files']);
      },
    );

    testWidgets(
      'a copied web link on macOS pastes as text, not the local file its path names',
      (tester) async {
        final directory = Directory.systemTemp.createTempSync(
          'discourse-native-clipboard-',
        );
        addTearDown(() => directory.deleteSync(recursive: true));
        final private = File('${directory.path}/draft.json')
          ..writeAsStringSync('{}');
        final link = 'https://attacker.example${private.path}';
        // pasteboard 0.5.0 answers `files` for a copied web link with the
        // link's path; the native file-URL read answers with nothing.
        final pluginCalls = _mockPasteboardPlugin(
          tester,
          files: [private.path],
        );
        _mockPasteboardFileUrls(tester, const []);
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          return switch (call.method) {
            'Clipboard.getData' => {'text': link},
            'Clipboard.hasStrings' => {'value': true},
            _ => null,
          };
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        const config = SiteConfig(authorizedExtensions: ['*']);
        final uploaded = <String>[];
        final composer = ComposerController(
          _target,
          canUploadImage: (name) => config.canUploadImage(name, staff: false),
          canUploadFile: (name) => config.canUploadFile(name, staff: false),
          imageUploader:
              (file, {required onProgress, required abortTrigger}) async {
                uploaded.add(file.name);
                throw StateError('A copied link must not upload a file');
              },
        );
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        composer.text.value = const TextEditingValue(
          text: 'See ',
          selection: TextSelection.collapsed(offset: 4),
        );
        await _pumpPanel(tester, shell, composer);

        await _pasteShortcut(tester);

        expect(composer.text.text, 'See $link');
        expect(composer.uploads, isEmpty);
        expect(uploaded, isEmpty);
        expect(composer.notice, isNull);
        expect(pluginCalls, isNot(contains('files')));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );

    for (final extension in ['png', 'mp4']) {
      testWidgets(
        'the paste shortcut uploads $extension at the captured caret',
        (tester) async {
          final clipboardResult = Completer<List<ComposerUploadFile>>();
          final calls = <_PanelUploadCall>[];
          var clipboardReads = 0;
          const config = SiteConfig(authorizedExtensions: ['png', 'mp4']);
          final composer = ComposerController(
            _target,
            canUploadImage: (name) => config.canUploadImage(name, staff: false),
            canUploadFile: (name) => config.canUploadFile(name, staff: false),
            imageUploader:
                (file, {required onProgress, required abortTrigger}) {
                  final call = _PanelUploadCall(onProgress);
                  calls.add(call);
                  return call.result.future;
                },
          );
          final shell = await _shell();
          addTearDown(composer.dispose);
          addTearDown(shell.dispose);
          composer.text.value = const TextEditingValue(
            text: 'BeforeAfter',
            selection: TextSelection.collapsed(offset: 6),
          );
          await _pumpPanel(
            tester,
            shell,
            composer,
            readClipboardFiles: () {
              clipboardReads++;
              return clipboardResult.future;
            },
          );

          await _pasteShortcut(tester);
          expect(clipboardReads, 1);

          // The native read is asynchronous. A later selection does not move the
          // upload away from the caret where Paste was invoked.
          composer.text.selection = const TextSelection.collapsed(offset: 11);
          clipboardResult.complete([
            ComposerUploadFile(
              name: 'photo.$extension',
              length: _file.length,
              openRead: _file.openRead,
            ),
          ]);
          await tester.pump();
          expect(calls, hasLength(1));
          expect(composer.notice, isNull);
          expect(composer.uploads.single.file.name, 'photo.$extension');

          calls.single.result.complete(
            ComposerUploadResult(
              id: 1,
              originalFilename: 'photo.$extension',
              shortUrl: 'upload://photo',
              url: 'https://meta.discourse.org/uploads/photo.$extension',
              thumbnailWidth: 640,
              thumbnailHeight: 480,
            ),
          );
          await tester.pump();

          expect(
            composer.text.text,
            extension == 'png'
                ? 'Before\n![photo|640x480](upload://photo)\nAfter'
                : 'Before\n![photo|video](upload://photo)\nAfter',
          );
          expect(
            composer.text.imageBlocks,
            hasLength(extension == 'png' ? 1 : 0),
          );
        },
      );
    }

    testWidgets('a late clipboard read cannot paste into a new composer', (
      tester,
    ) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        return switch (call.method) {
          'Clipboard.getData' => {'text': 'stale paste'},
          'Clipboard.hasStrings' => {'value': true},
          _ => null,
        };
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final clipboardResult = Completer<List<ComposerUploadFile>>();
      final original = ComposerController(
        _target,
        imageUploader: (_, {required onProgress, required abortTrigger}) =>
            Completer<ComposerUploadResult>().future,
      );
      final replacement = ComposerController(
        _target,
        imageUploader: (_, {required onProgress, required abortTrigger}) =>
            Completer<ComposerUploadResult>().future,
      )..text.text = 'New draft';
      final shell = await _shell();
      addTearDown(original.dispose);
      addTearDown(replacement.dispose);
      addTearDown(shell.dispose);
      await _pumpPanel(
        tester,
        shell,
        original,
        readClipboardFiles: () => clipboardResult.future,
      );

      await _pasteShortcut(tester);
      await _pumpPanel(
        tester,
        shell,
        replacement,
        readClipboardFiles: () async => const [],
      );
      clipboardResult.complete(const []);
      await tester.pump();

      expect(replacement.text.text, 'New draft');
      expect(replacement.uploads, isEmpty);
    });

    for (final contextMenu in [false, true]) {
      testWidgets('pasting a URL links selected text (menu: $contextMenu)', (
        tester,
      ) async {
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          return switch (call.method) {
            'Clipboard.getData' => {'text': 'https://discourse.org'},
            'Clipboard.hasStrings' => {'value': true},
            _ => null,
          };
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        final composer = ComposerController(_target);
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        const before = TextEditingValue(
          text: 'Visit Discourse today',
          selection: TextSelection(baseOffset: 15, extentOffset: 6),
        );
        composer.text.value = before;
        await _pumpPanel(tester, shell, composer);

        if (contextMenu) {
          final textField = tester.widget<TextField>(
            find.byType(TextField).last,
          );
          final editable = tester.state<EditableTextState>(
            find.byType(EditableText).last,
          );
          final toolbar =
              textField.contextMenuBuilder!(editable.context, editable)
                  as AdaptiveTextSelectionToolbar;
          toolbar.buttonItems!
              .singleWhere((item) => item.type == ContextMenuButtonType.paste)
              .onPressed!();
          await tester.pumpAndSettle();
        } else {
          await _pasteShortcut(tester);
        }

        expect(
          composer.text.text,
          'Visit [Discourse](https://discourse.org) today',
        );
        expect(
          composer.text.selection,
          const TextSelection.collapsed(offset: 40),
        );
        composer.history.undo();
        expect(composer.text.value, before);
        composer.history.redo();
        expect(
          composer.text.text,
          'Visit [Discourse](https://discourse.org) today',
        );
      });
    }

    testWidgets('a delayed URL paste does not replace a changed selection', (
      tester,
    ) async {
      final clipboard = Completer<Object?>();
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        return switch (call.method) {
          'Clipboard.getData' => clipboard.future,
          'Clipboard.hasStrings' => {'value': true},
          _ => null,
        };
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final composer = ComposerController(_target);
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.value = const TextEditingValue(
        text: 'Visit Discourse today',
        selection: TextSelection(baseOffset: 6, extentOffset: 15),
      );
      await _pumpPanel(tester, shell, composer);
      await _pasteShortcut(tester);
      composer.text.selection = const TextSelection.collapsed(offset: 20);
      clipboard.complete({'text': 'https://discourse.org'});
      await tester.pumpAndSettle();
      expect(composer.text.text, 'Visit Discourse today');
      expect(
        composer.text.selection,
        const TextSelection.collapsed(offset: 20),
      );
    });

    testWidgets('plain text paste keeps Flutter clipboard behavior', (
      tester,
    ) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        return switch (call.method) {
          'Clipboard.getData' => {'text': ' pasted '},
          'Clipboard.hasStrings' => {'value': true},
          _ => null,
        };
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      final composer = ComposerController(
        _target,
        imageUploader: (_, {required onProgress, required abortTrigger}) =>
            Completer<ComposerUploadResult>().future,
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.value = const TextEditingValue(
        text: 'BeforeAfter',
        selection: TextSelection.collapsed(offset: 6),
      );
      await _pumpPanel(
        tester,
        shell,
        composer,
        readClipboardFiles: () async => const [],
      );

      await _pasteShortcut(tester);

      expect(composer.text.text, 'Before pasted After');
      expect(composer.uploads, isEmpty);
    });

    for (final extension in ['png', 'mp4']) {
      testWidgets(
        'the context menu offers $extension paste without clipboard text',
        (tester) async {
          final calls = <_PanelUploadCall>[];
          const config = SiteConfig(authorizedExtensions: ['png', 'mp4']);
          final composer = ComposerController(
            _target,
            canUploadImage: (name) => config.canUploadImage(name, staff: false),
            canUploadFile: (name) => config.canUploadFile(name, staff: false),
            imageUploader:
                (file, {required onProgress, required abortTrigger}) {
                  final call = _PanelUploadCall(onProgress);
                  calls.add(call);
                  return call.result.future;
                },
          );
          final shell = await _shell();
          addTearDown(composer.dispose);
          addTearDown(shell.dispose);
          await _pumpPanel(
            tester,
            shell,
            composer,
            readClipboardFiles: () async => [
              ComposerUploadFile(
                name: 'photo.$extension',
                length: _file.length,
                openRead: _file.openRead,
              ),
            ],
          );

          final textField = tester.widget<TextField>(
            find.byType(TextField).last,
          );
          final editable = tester.state<EditableTextState>(
            find.byType(EditableText).last,
          );
          final toolbar =
              textField.contextMenuBuilder!(editable.context, editable)
                  as AdaptiveTextSelectionToolbar;
          final paste = toolbar.buttonItems!.singleWhere(
            (item) => item.type == ContextMenuButtonType.paste,
          );
          paste.onPressed!();
          await tester.pump();

          expect(calls, hasLength(1));
          expect(composer.notice, isNull);
          expect(composer.uploads.single.file.name, 'photo.$extension');
        },
      );
    }

    testWidgets(
      'paste rejects files disallowed by the site without inserting text',
      (tester) async {
        const config = SiteConfig(authorizedExtensions: ['png']);
        final composer = ComposerController(
          _target,
          canUploadImage: (name) => config.canUploadImage(name, staff: false),
          canUploadFile: (name) => config.canUploadFile(name, staff: false),
          imageUploader:
              (_, {required onProgress, required abortTrigger}) async {
                fail('Disallowed clipboard files must not be uploaded');
              },
        )..text.text = 'Draft';
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          return switch (call.method) {
            'Clipboard.getData' => {'text': '/tmp/blocked.mp4'},
            'Clipboard.hasStrings' => {'value': true},
            _ => null,
          };
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        await _pumpPanel(
          tester,
          shell,
          composer,
          readClipboardFiles: () async => [
            ComposerUploadFile(
              name: 'blocked.mp4',
              length: _file.length,
              openRead: _file.openRead,
            ),
          ],
        );

        await _pasteShortcut(tester);

        expect(composer.notice, 'That file type is not allowed on this site.');
        expect(composer.uploads, isEmpty);
        expect(composer.text.text, 'Draft');
      },
    );

    testWidgets('the upload button picks images at the captured caret', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      final pickerResult = Completer<List<ComposerUploadFile>>();
      final calls = <_PanelUploadCall>[];
      var pickerCalls = 0;
      final composer = ComposerController(
        _target,
        imageUploader: (file, {required onProgress, required abortTrigger}) {
          final call = _PanelUploadCall(onProgress);
          calls.add(call);
          return call.result.future;
        },
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.value = const TextEditingValue(
        text: 'BeforeAfter',
        selection: TextSelection.collapsed(offset: 6),
      );
      await _pumpPanel(
        tester,
        shell,
        composer,
        pickImages: () {
          pickerCalls++;
          return pickerResult.future;
        },
      );

      expect(find.byTooltip('Upload'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('composer-upload')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-upload-photos')));
      await tester.pump();
      expect(pickerCalls, 1);
      expect(
        tester
            .widget<DButton>(find.byKey(const ValueKey('composer-upload')))
            .onPressed,
        isNull,
      );

      // Crossing the compact footer breakpoint while the platform dialog owns
      // the window must not replace the button state that is awaiting it.
      final pixelRatio = tester.view.devicePixelRatio;
      tester.view.physicalSize = Size(390 * pixelRatio, 844 * pixelRatio);
      await tester.pump();

      // The native dialog owns focus while it is open. Its result still belongs
      // at the caret from when the user pressed Upload.
      composer.text.selection = const TextSelection.collapsed(offset: 11);
      pickerResult.complete([_file]);
      await tester.pump();
      expect(calls, hasLength(1));

      calls.single.result.complete(
        const ComposerUploadResult(
          id: 1,
          originalFilename: 'photo.png',
          shortUrl: 'upload://photo',
          url: 'https://meta.discourse.org/uploads/photo.png',
          thumbnailWidth: 640,
          thumbnailHeight: 480,
        ),
      );
      await tester.pump();

      expect(
        composer.text.text,
        'Before\n![photo|640x480](upload://photo)\nAfter',
      );
      expect(composer.focus.hasFocus, isTrue);
    });

    testWidgets(
      'the upload button carries its caret through uploads finishing meanwhile',
      (tester) async {
        final pickerResult = Completer<List<ComposerUploadFile>>();
        final calls = <_PanelUploadCall>[];
        final composer = ComposerController(
          _target,
          imageUploader: (file, {required onProgress, required abortTrigger}) {
            final call = _PanelUploadCall(onProgress);
            calls.add(call);
            return call.result.future;
          },
        );
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        composer.text.value = const TextEditingValue(
          text: 'Before',
          selection: TextSelection.collapsed(offset: 6),
        );
        composer.addImages([_file], 6);
        await _pumpPanel(
          tester,
          shell,
          composer,
          pickImages: () => pickerResult.future,
        );

        // The pending upload's progress keeps animating, so the menu is
        // pumped open rather than settled.
        await tester.tap(find.byKey(const ValueKey('composer-upload')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.tap(find.byKey(const ValueKey('composer-upload-photos')));
        await tester.pump();

        // The earlier upload swaps its placeholder for longer Markdown while
        // the dialog is open, so the caret captured at Upload has moved.
        calls.single.result.complete(
          const ComposerUploadResult(
            id: 1,
            originalFilename: 'first.png',
            shortUrl: 'upload://first',
            url: 'https://meta.discourse.org/uploads/first.png',
            thumbnailWidth: 640,
            thumbnailHeight: 480,
          ),
        );
        await tester.pump();
        expect(
          composer.text.text,
          'Before\n![first|640x480](upload://first)\n',
        );

        pickerResult.complete([_file]);
        await tester.pump();
        expect(calls, hasLength(2));
        calls.last.result.complete(
          const ComposerUploadResult(
            id: 2,
            originalFilename: 'photo.png',
            shortUrl: 'upload://photo',
            url: 'https://meta.discourse.org/uploads/photo.png',
            thumbnailWidth: 640,
            thumbnailHeight: 480,
          ),
        );
        await tester.pump();

        expect(
          composer.text.text,
          'Before\n'
          '![first|640x480](upload://first)\n'
          '![photo|640x480](upload://photo)\n',
        );
      },
    );

    testWidgets(
      "the photo library resizes and encodes as the site's composer would",
      (tester) async {
        final previousPicker = images.ImagePickerPlatform.instance;
        final picker = _RecordingImagePicker();
        images.ImagePickerPlatform.instance = picker;
        addTearDown(() => images.ImagePickerPlatform.instance = previousPicker);
        const config = SiteConfig(
          composerImageOptimization: ComposerImageOptimization(
            resizeWidthTarget: 1280,
            encodeQuality: 75,
          ),
        );
        final shell = ShellController(
          instanceStore: FakeInstanceStore([
            instance('meta.discourse.org').copyWith(config: config),
          ]),
          api: FakeDiscourseApi(siteConfigs: {_target.siteUrl: config}),
          authenticator: FakeAuthenticator(),
          drafts: FakeDraftStore(),
          trackers: FakeSiteTracker.reset(),
        );
        await shell.load();
        final composer = ComposerController(
          _target,
          simultaneousUploads: 6,
          imageUploader: (_, {required onProgress, required abortTrigger}) =>
              Completer<ComposerUploadResult>().future,
        );
        addTearDown(shell.dispose);
        addTearDown(composer.dispose);
        expect(shell.siteConfigFor(_target.siteUrl), config);
        await _pumpPanel(tester, shell, composer, pickImages: null);

        await tester.tap(find.byKey(const ValueKey('composer-upload')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('composer-upload-photos')));
        await tester.pumpAndSettle();

        final options = picker.options!;
        expect(options.imageOptions.maxWidth, 1280);
        expect(options.imageOptions.imageQuality, 75);
        expect(options.limit, 6);
      },
    );

    testWidgets('the upload button follows composer availability', (
      tester,
    ) async {
      final shell = await _shell();
      final unavailable = ComposerController(_target);
      addTearDown(shell.dispose);
      addTearDown(unavailable.dispose);
      await _pumpPanel(tester, shell, unavailable);
      expect(find.byKey(const ValueKey('composer-upload')), findsNothing);

      final available = ComposerController(
        _target,
        imageUploader: (_, {required onProgress, required abortTrigger}) =>
            Completer<ComposerUploadResult>().future,
      )..beginLoadingBody();
      addTearDown(available.dispose);
      await _pumpPanel(tester, shell, available);
      expect(
        tester
            .widget<DButton>(find.byKey(const ValueKey('composer-upload')))
            .onPressed,
        isNull,
      );

      available.loadedBody('Existing body');
      await tester.pump();
      expect(
        tester
            .widget<DButton>(find.byKey(const ValueKey('composer-upload')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('the panel shows rate-limit recovery and retry actions', (
      tester,
    ) async {
      final calls = <_PanelUploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: (file, {required onProgress, required abortTrigger}) {
          final call = _PanelUploadCall(onProgress);
          calls.add(call);
          return call.result.future;
        },
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpPanel(tester, shell, composer);

      expect(find.text('Write a reply…'), findsOneWidget);
      composer.text.text = 'body';
      composer.addImages([_file], 4);
      calls.single.onProgress(0.37);
      await tester.pump();

      expect(find.text('Write a reply…'), findsNothing);
      expect(find.text('photo.png'), findsOneWidget);
      expect(find.text('Uploading · 37%'), findsOneWidget);
      expect(find.byTooltip('Cancel upload'), findsOneWidget);
      calls.single.result.completeError(
        const ComposerUploadException(
          'server error',
          statusCode: 429,
          retryAfter: Duration(seconds: 120),
        ),
      );
      await tester.pump();

      expect(
        find.text('Too many uploads. Try again in 120 seconds.'),
        findsOneWidget,
      );
      expect(find.byTooltip('Retry upload'), findsOneWidget);
      expect(find.byTooltip('Remove upload'), findsOneWidget);

      await tester.tap(find.byTooltip('Retry upload'));
      await tester.pump();
      expect(calls, hasLength(2));
      expect(find.text('Retrying · 0%'), findsOneWidget);

      await tester.tap(find.byTooltip('Cancel upload'));
      await tester.pump();
      expect(find.text('photo.png'), findsNothing);
    });
    testWidgets('the panel shows progress and failed upload actions', (
      tester,
    ) async {
      final calls = <_PanelUploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: (file, {required onProgress, required abortTrigger}) {
          final call = _PanelUploadCall(onProgress);
          calls.add(call);
          return call.result.future;
        },
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpPanel(tester, shell, composer);

      expect(find.text('Write a reply…'), findsOneWidget);
      composer.text.text = 'body';
      composer.addImages([_file], 4);
      calls.single.onProgress(0.37);
      await tester.pump();

      expect(find.text('Write a reply…'), findsNothing);
      expect(find.text('photo.png'), findsOneWidget);
      expect(find.text('Uploading · 37%'), findsOneWidget);
      expect(find.byTooltip('Cancel upload'), findsOneWidget);
      calls.single.result.completeError(
        const ComposerUploadException('The image is too large.'),
      );
      await tester.pump();

      expect(find.text('The image is too large.'), findsOneWidget);
      expect(find.byTooltip('Retry upload'), findsOneWidget);
      expect(find.byTooltip('Remove upload'), findsOneWidget);

      await tester.tap(find.byTooltip('Retry upload'));
      await tester.pump();
      expect(calls, hasLength(2));
      expect(find.text('Retrying · 0%'), findsOneWidget);

      await tester.tap(find.byTooltip('Cancel upload'));
      await tester.pump();
      expect(find.text('photo.png'), findsNothing);
    });

    testWidgets('a file refused for its size offers no retry', (tester) async {
      var calls = 0;
      final composer = ComposerController(
        _target,
        imageUploader: (file, {required onProgress, required abortTrigger}) {
          calls++;
          throw ComposerUploadException.tooLarge(
            file.name,
            maxBytes: 10 * 1024 * 1024,
          );
        },
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpPanel(tester, shell, composer);

      composer.text.text = 'body';
      composer.addFiles([
        ComposerUploadFile(
          name: 'clip.mov',
          length: _file.length,
          openRead: _file.openRead,
        ),
      ], 4);
      await tester.pump();

      expect(
        find.text('clip.mov is too large (maximum size is 10 MB).'),
        findsOneWidget,
      );
      expect(find.byTooltip('Retry upload'), findsNothing);
      expect(find.byTooltip('Remove upload'), findsOneWidget);
      composer.retryUpload(composer.uploads.single.id);
      await tester.pump();
      expect(calls, 1);
      expect(composer.uploads.single.status, ComposerUploadStatus.failed);

      await tester.tap(find.byTooltip('Remove upload'));
      await tester.pump();
      expect(composer.uploads, isEmpty);
    });
  });

  group('image selection and editing', () {
    testWidgets('vertical arrows leave a selected projected image', (
      tester,
    ) async {
      final calls = <_PanelUploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: (file, {required onProgress, required abortTrigger}) {
          final call = _PanelUploadCall(onProgress);
          calls.add(call);
          return call.result.future;
        },
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      await _pumpPanel(tester, shell, composer);

      composer.text.text = 'Before\n';
      composer.addImages([_file], composer.text.text.length);
      calls.single.result.complete(
        const ComposerUploadResult(
          id: 42,
          originalFilename: 'photo.png',
          shortUrl: 'upload://photo',
          url: 'https://meta.discourse.org/uploads/photo.png',
          width: 640,
          height: 480,
        ),
      );
      await tester.pump();

      final image = composer.text.imageBlocks.single;
      final source = composer.text.text;
      expect(
        composer.text.selection,
        TextSelection.collapsed(offset: image.end + 1),
      );
      expect(composer.text.keyboardSelectedImage, isNull);
      expect(
        find.byKey(const ValueKey('composer-image-description')),
        findsNothing,
      );
      expect(
        tester
            .widget<ComposerImagePreview>(find.byType(ComposerImagePreview))
            .highlighted,
        isFalse,
      );

      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();

      // There is one real line below the image, so Up selects the image
      // directly without stopping on a synthetic blank line.
      await tester.pumpAndSettle();
      expect(composer.text.text, source);
      expect(
        composer.text.selection,
        TextSelection.collapsed(offset: image.end),
      );
      expect(composer.text.keyboardSelectedImage, isNotNull);
      expect(find.byType(ComposerImagePreview), findsOneWidget);
      expect(
        tester
            .widget<ComposerImagePreview>(find.byType(ComposerImagePreview))
            .highlighted,
        isTrue,
      );
      expect(_composerEditable(tester).showCursor, isFalse);
      expect(find.byTooltip('Decrease image size'), findsOneWidget);
      expect(find.byTooltip('Increase image size'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('composer-image-description')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('composer-image-description')).hitTestable(),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();

      expect(
        composer.text.selection,
        TextSelection.collapsed(offset: image.start - 1),
      );
      expect(composer.text.keyboardSelectedImage, isNull);
      expect(_composerEditable(tester).showCursor, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(composer.text.keyboardSelectedImage, isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(
        composer.text.selection,
        TextSelection.collapsed(offset: image.end),
      );
      expect(composer.text.keyboardSelectedImage, isNull);
      expect(_composerEditable(tester).showCursor, isTrue);
    });

    testWidgets('escape unselects an upload before closing the composer', (
      tester,
    ) async {
      final composer = ComposerController(
        _target,
        onSaveDraft: (save) async => save.sequence + 1,
        resolveUploadUrls: (_) async => const {},
      );
      final shell = await _InteractionTrackingShellController.create();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text = '![old|640x480](upload://photo)';
      await _pumpPanel(tester, shell, composer);

      final image = composer.text.imageBlocks.single;
      composer.text.selection = TextSelection.collapsed(offset: image.end);
      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(composer.text.keyboardSelectedImage, isNotNull);
      expect(
        find.byKey(const ValueKey('composer-image-description')),
        findsOneWidget,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(composer.text.keyboardSelectedImage, isNull);
      expect(
        find.byKey(const ValueKey('composer-image-description')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('composer-frame')), findsOneWidget);
      expect(shell.closeCalls, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(shell.closeCalls, 1);
      composer.draftSettled();
    });

    testWidgets('selecting a projected image shows its editing controls', (
      tester,
    ) async {
      final composer = ComposerController(
        _target,
        resolveUploadUrls: (_) async => const {},
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text = '![old|640x480](upload://photo)';
      await _pumpPanel(tester, shell, composer);

      expect(find.byType(ComposerImagePreview), findsOneWidget);
      final previewRect = tester.getRect(find.byType(ComposerImagePreview));
      final editorRect = tester.getRect(
        find.byWidgetPredicate(
          (widget) =>
              widget is EditableText &&
              identical(widget.controller, composer.text),
        ),
      );
      expect(previewRect.top, greaterThanOrEqualTo(editorRect.top));
      Future<void> tapPreview({bool redrawBeforeUp = false}) async {
        final position =
            tester.getTopLeft(find.byType(ComposerImagePreview)) +
            const Offset(8, 8);
        final gesture = await tester.startGesture(position);
        if (redrawBeforeUp) {
          final image = composer.text.imageBlocks.single;
          composer.text.selection = TextSelection.collapsed(
            offset: image.start + 1,
          );
          await tester.pump();
          expect(find.byType(ComposerImagePreview), findsOneWidget);
        }
        await gesture.up();
      }

      await tapPreview(redrawBeforeUp: true);
      await tester.pump();
      await tester.pump();

      final image = composer.text.imageBlocks.single;
      expect(
        composer.text.selection,
        TextSelection.collapsed(offset: image.end),
      );
      expect(composer.text.keyboardSelectedImage, isNotNull);
      expect(
        tester
            .widget<ComposerImagePreview>(find.byType(ComposerImagePreview))
            .highlighted,
        isTrue,
      );
      expect(find.byTooltip('Decrease image size'), findsOneWidget);
      expect(find.byTooltip('Increase image size'), findsOneWidget);
      expect(find.byTooltip('Delete image'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('composer-image-description')),
        findsOneWidget,
      );
      composer.text.selection = TextSelection.collapsed(offset: image.end - 1);
      await tester.pump();
      expect(find.byType(ComposerImagePreview), findsOneWidget);
      final altField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Add image description',
      );
      await tester.enterText(altField, 'draft alt');

      await tester.tap(find.byTooltip('Decrease image size'));
      await tester.pump();
      await tester.pump();
      expect(composer.text.text, '![draft alt|640x480, 75%](upload://photo)');
      expect(composer.text.keyboardSelectedImage, isNotNull);
      expect(
        tester
            .widget<ComposerImagePreview>(find.byType(ComposerImagePreview))
            .highlighted,
        isTrue,
      );
      expect(
        find.byKey(const ValueKey('composer-image-description')),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(altField).controller!.text, 'draft alt');

      await tester.tap(find.byTooltip('Decrease image size'));
      await tester.pump();
      await tester.pump();
      expect(composer.text.text, '![draft alt|640x480, 50%](upload://photo)');
      expect(composer.text.keyboardSelectedImage, isNotNull);
      expect(
        find.byKey(const ValueKey('composer-image-description')),
        findsOneWidget,
      );

      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(composer.text.keyboardSelectedImage, isNull);
      expect(_composerEditable(tester).showCursor, isTrue);
      expect(
        find.byKey(const ValueKey('composer-image-description')),
        findsNothing,
      );

      final resizedImage = composer.text.imageBlocks.single;
      composer.text.selection = TextSelection.collapsed(
        offset: resizedImage.end,
      );
      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(composer.text.keyboardSelectedImage, isNotNull);
      expect(
        find.byKey(const ValueKey('composer-image-description')),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(composer.text.selection.extentOffset, resizedImage.end);
      expect(composer.text.keyboardSelectedImage, isNull);
      expect(
        find.byKey(const ValueKey('composer-image-description')),
        findsNothing,
      );
      expect(
        tester
            .widget<ComposerImagePreview>(find.byType(ComposerImagePreview))
            .highlighted,
        isFalse,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(composer.text.keyboardSelectedImage, isNotNull);
      expect(
        find.byKey(const ValueKey('composer-image-description')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.hintText == 'Add image description',
        ),
        'new [alt]',
      );
      await tester.tap(
        find.byKey(const ValueKey('composer-image-description')),
      );
      await tester.pump();
      expect(
        composer.text.text,
        r'![new \[alt\]|640x480, 50%](upload://photo)',
      );

      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(composer.text.keyboardSelectedImage, isNull);
      expect(composer.text.text, isEmpty);
    });

    testWidgets('an image taller than the editor scrolls inside it', (
      tester,
    ) async {
      final composer = ComposerController(
        _target,
        resolveUploadUrls: (_) async => const {},
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text = '![tall|640x480](upload://photo)';
      await _pumpPanel(tester, shell, composer, height: 340);
      await tester.pumpAndSettle();

      final editor = find.byType(EditableText);
      final scrollable = find.descendant(
        of: editor,
        matching: find.byType(Scrollable),
      );
      final scrollState = tester.state<ScrollableState>(scrollable);
      expect(scrollState.position.maxScrollExtent, greaterThan(0));
      scrollState.position.jumpTo(0);
      await tester.pump();

      final image = composer.text.imageBlocks.single;
      final oldTop = composer.text.collapsedImageGlobalRect(image)!.top;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getRect(find.byType(TextField)).center,
          scrollDelta: const Offset(0, 80),
        ),
      );
      await tester.pumpAndSettle();

      expect(scrollState.position.pixels, greaterThan(0));
      expect(
        composer.text.collapsedImageGlobalRect(image)!.top,
        lessThan(oldTop),
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });

  group('gallery editing', () {
    testWidgets('Enter before text following a gallery preserves the gallery', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      final pixelRatio = tester.view.devicePixelRatio;
      tester.view.physicalSize = Size(1455 * pixelRatio, 1022 * pixelRatio);
      final composer = ComposerController(
        _target,
        resolveUploadUrls: (_) async => const {},
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      const source =
          '[grid]\n'
          '![one|640x480](upload://one)\n'
          '![two|640x480](upload://two)\n'
          '[/grid]\n'
          'dog\n'
          '![dog|640x480](upload://dog)';
      // RenderEditable can leave the caret at the first layout-neutral source
      // offset even though it is painted immediately before the following
      // prose. Typing Enter from this reported state used to split `[grid]`.
      composer.text.value = const TextEditingValue(
        text: source,
        selection: TextSelection.collapsed(offset: 2),
      );

      await _pumpPanel(tester, shell, composer, height: 900);
      await tester.pumpAndSettle();

      final galleryEnd = composer.text.galleryBlocks.single.end;
      final tappedValue = composer.text.value;
      final caret = tappedValue.selection.extentOffset;
      expect(caret, 2);
      tester.testTextInput.updateEditingValue(
        tappedValue.copyWith(
          text: tappedValue.text.replaceRange(caret, caret, '\n'),
          selection: TextSelection.collapsed(offset: caret + 1),
        ),
      );
      await tester.pump();

      expect(
        composer.text.text,
        source.replaceRange(galleryEnd, galleryEnd, '\n'),
      );
      expect(composer.text.galleryBlocks, hasLength(1));
    });

    testWidgets('gallery and member toolbars edit mode and membership', (
      tester,
    ) async {
      final composer = ComposerController(
        _target,
        resolveUploadUrls: (_) async => const {},
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      // A terminal gallery has no caret line after it; the prose below is
      // where an image dragged out of the gallery lands.
      composer.text.text =
          '[grid]\n'
          '![one|640x480](upload://one)\n'
          '![two|640x480](upload://two)\n'
          '[/grid]\n\nAfter';
      composer.text.selection = const TextSelection.collapsed(offset: 0);
      await _pumpPanel(tester, shell, composer);
      await tester.pumpAndSettle();

      final preview = find.byType(ComposerImageGalleryPreview);
      expect(preview, findsOneWidget);
      final parsedGallery = composer.text.galleryBlocks.single;
      final projectedRect = composer.text.collapsedGalleryGlobalRect(
        parsedGallery,
      )!;
      final galleryTap = Offset(projectedRect.right - 8, projectedRect.top + 8);
      expect(
        tester.getRect(find.byType(EditableText)).contains(galleryTap),
        isTrue,
        reason: 'the gallery control should be inside the editor viewport',
      );
      expect(
        projectedRect.contains(galleryTap),
        isTrue,
        reason: 'the visible gallery control should be hit-testable',
      );
      expect(
        composer.text.collapsedGalleryAtGlobalPosition(galleryTap),
        isNotNull,
      );
      await tester.tapAt(galleryTap);
      await tester.pump();
      await tester.pump();

      expect(
        composer.text.selection.extentOffset,
        composer.text.galleryBlocks.single.end,
        reason: 'a gallery background tap should select the gallery',
      );
      expect(
        composer.text.collapsedGalleryGlobalRect(
          composer.text.galleryBlocks.single,
        ),
        isNotNull,
      );
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsOneWidget,
      );
      expect(
        tester.widget<ComposerImageGalleryPreview>(preview).highlighted,
        isTrue,
      );
      expect(find.byTooltip('Add images to gallery'), findsOneWidget);
      expect(find.byTooltip('Remove gallery, keep images'), findsOneWidget);
      expect(find.byTooltip('Close gallery controls'), findsNothing);
      await tester.tap(find.byTooltip('Carousel gallery mode'));
      await tester.pump();
      expect(composer.text.text, contains('[grid mode=carousel]'));
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsOneWidget,
      );

      final currentGallery = parseComposerImageGalleries(
        composer.text.text,
      ).single;
      final firstImageRect = composer.text.collapsedImageGlobalRect(
        currentGallery.images.first,
      )!;
      final imageTap = Offset(
        firstImageRect.center.dx,
        firstImageRect.top + 22,
      );
      expect(composer.text.collapsedImageAtGlobalPosition(imageTap), isNotNull);
      expect(
        tester
            .getRect(find.byKey(const ValueKey('composer-gallery-toolbar')))
            .contains(imageTap),
        isFalse,
        reason: 'an image member must retain a 44px interaction target',
      );
      await tester.tapAt(imageTap);
      await tester.pump();
      await tester.pump();
      expect(composer.text.keyboardSelectedImage?.url, 'upload://one');
      expect(
        tester.widget<ComposerImageGalleryPreview>(preview).highlighted,
        isFalse,
      );
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsNothing,
      );
      expect(find.byTooltip('Move image outside gallery'), findsNothing);
      expect(find.byTooltip('Delete image'), findsOneWidget);
      expect(find.byTooltip('Decrease image size'), findsNothing);

      final dragStart = composer.text
          .collapsedImageGlobalRect(currentGallery.images.first)!
          .center;
      final editorRect = tester.getRect(
        find.byWidgetPredicate(
          (widget) =>
              widget is EditableText &&
              identical(widget.controller, composer.text),
        ),
      );
      final dropPosition = Offset(editorRect.left + 8, editorRect.bottom - 4);
      final drag = await tester.startGesture(
        dragStart,
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveTo(dropPosition);
      await drag.up();
      await tester.pumpAndSettle();
      final gallery = parseComposerImageGalleries(composer.text.text).single;
      expect(gallery.images.single.url, 'upload://two');
      expect(composer.standaloneImages.single.url, 'upload://one');

      final remainingRect = composer.text.collapsedImageGlobalRect(
        gallery.images.single,
      )!;
      await tester.tapAt(remainingRect.center);
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Delete image'));
      await tester.pump();
      expect(composer.text.galleryBlocks, isEmpty);
      expect(composer.text.imageBlocks.map((image) => image.url), [
        'upload://one',
      ]);
    });

    testWidgets('gallery toolbar fits its controls in a narrow composer', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        addTearDown(tester.view.resetPhysicalSize);
        final pixelRatio = tester.view.devicePixelRatio;
        tester.view.physicalSize = Size(280 * pixelRatio, 700 * pixelRatio);
        final composer = ComposerController(
          _target,
          resolveUploadUrls: (_) async => const {},
        );
        final shell = await _shell();
        addTearDown(composer.dispose);
        addTearDown(shell.dispose);
        composer.text.value = const TextEditingValue(
          text:
              '[grid]\n'
              '![one](upload://one)\n'
              '![two](upload://two)\n'
              '![three](upload://three)\n'
              '[/grid]',
          selection: TextSelection.collapsed(offset: 0),
        );

        await _pumpPanel(tester, shell, composer);
        await tester.pumpAndSettle();
        final editableRect = tester.getRect(find.byType(EditableText));
        final previewRect = tester.getRect(
          find.byType(ComposerImageGalleryPreview),
        );
        expect(previewRect.left, greaterThanOrEqualTo(editableRect.left));
        expect(previewRect.right, lessThanOrEqualTo(editableRect.right));
        await tester.tapAt(Offset(previewRect.right - 8, previewRect.top + 8));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final toolbar = find.byKey(const ValueKey('composer-gallery-toolbar'));
        expect(toolbar, findsOneWidget);
        final toolbarRect = tester.getRect(toolbar);
        expect(toolbarRect.size, const Size(44 * 4, 44));
        final viewport = Rect.fromLTWH(
          0,
          0,
          tester.view.physicalSize.width / pixelRatio,
          tester.view.physicalSize.height / pixelRatio,
        );
        expect(viewport.contains(toolbarRect.topLeft), isTrue);
        expect(viewport.contains(toolbarRect.bottomRight), isTrue);

        final iconButtons = find.descendant(
          of: toolbar,
          matching: find.byType(DButton),
        );
        expect(iconButtons, findsNWidgets(2));
        for (final button in iconButtons.evaluate()) {
          final size = tester.getSize(find.byWidget(button.widget));
          final tooltip = (button.widget as DButton).tooltip;
          expect(size.width, greaterThanOrEqualTo(44), reason: tooltip);
          expect(size.height, greaterThanOrEqualTo(44), reason: tooltip);
        }

        final modeToggles = find.descendant(
          of: toolbar,
          matching: find.byType(DToggle),
        );
        expect(modeToggles, findsNWidgets(2));
        for (final button in modeToggles.evaluate()) {
          final size = tester.getSize(find.byWidget(button.widget));
          expect(size.width, 44);
          expect(size.height, 44);
        }

        Finder modeButton(String tooltip) => find.bySemanticsLabel(tooltip);
        expect(
          tester.getSemantics(modeButton('Grid gallery mode')),
          isSemantics(
            label: 'Grid gallery mode',
            isButton: true,
            hasToggledState: true,
            isToggled: true,
          ),
        );
        expect(
          tester.getSemantics(modeButton('Carousel gallery mode')),
          isSemantics(
            label: 'Carousel gallery mode',
            isButton: true,
            hasToggledState: true,
            isToggled: false,
          ),
        );
        await tester.tap(find.byTooltip('Carousel gallery mode'));
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(modeButton('Grid gallery mode')),
          isSemantics(hasToggledState: true, isToggled: false),
        );
        expect(
          tester.getSemantics(modeButton('Carousel gallery mode')),
          isSemantics(hasToggledState: true, isToggled: true),
        );
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('standalone image moves to the displayed block boundary', (
      tester,
    ) async {
      final composer = ComposerController(
        _target,
        resolveUploadUrls: (_) async => const {},
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      const image = '![outside|100x60](upload://outside)';
      composer.text.text =
          'testc\n[grid]\n![inside|100x60](upload://inside)\n[/grid]\n\ntest\n\n$image';
      await _pumpPanel(tester, shell, composer);
      await tester.pumpAndSettle();
      final editable = tester
          .state<EditableTextState>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is EditableText &&
                  identical(widget.controller, composer.text),
            ),
          )
          .renderEditable;
      final offset = composer.text.text.indexOf('\ntest\n') + 1;
      final destination = editable.localToGlobal(
        editable.getLocalRectForCaret(TextPosition(offset: offset)).topLeft +
            const Offset(0, 1),
      );
      final surface = tester.widget<ComposerBlockSurface>(
        find.byType(ComposerBlockSurface),
      );
      final blocks = composer.blocks.index.blocks;
      final gapCenter =
          (surface.blockRect(blocks[1])!.bottom +
              surface.blockRect(blocks[2])!.top) /
          2;
      final start = composer.text
          .collapsedImageGlobalRect(composer.standaloneImages.single)!
          .center;
      final drag = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveTo(destination);
      await tester.pump();
      expect(
        tester.getCenter(find.byType(DDropIndicator)).dy,
        closeTo(gapCenter, .01),
      );
      await drag.moveTo(const Offset(0, 0));
      await tester.pump();
      expect(find.byType(DDropIndicator), findsNothing);
      await drag.moveTo(destination);
      await tester.pump();
      expect(find.byType(DDropIndicator), findsOneWidget);
      await drag.up();
      await tester.pumpAndSettle();
      expect(find.byType(DDropIndicator), findsNothing);
      expect(
        composer.text.text.indexOf(image),
        lessThan(composer.text.text.indexOf('\ntest\n')),
      );
      expect(composer.standaloneImages, hasLength(1));
      expect(
        composer.text.galleryBlocks.single.images.single.url,
        'upload://inside',
      );
    });

    testWidgets('gallery tiles can be reordered by drag and drop', (
      tester,
    ) async {
      final composer = ComposerController(
        _target,
        resolveUploadUrls: (_) async => const {},
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text =
          '[grid]\n'
          '![one](upload://one)\n'
          '![two](upload://two)\n'
          '![three](upload://three)\n'
          '[/grid]';

      await _pumpPanel(tester, shell, composer);
      await tester.pumpAndSettle();

      final tiles = find.byType(ComposerImageGalleryTile);
      final first = tester.getCenter(tiles.at(0));
      final last = tester.getCenter(tiles.at(2));
      final drag = await tester.startGesture(
        first,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      for (var step = 1; step <= 10; step++) {
        await drag.moveTo(Offset.lerp(first, last, step / 10)!);
        if (step == 3) {
          final draggedImage = composer.text.galleryBlocks.single.images.first;
          composer.text.selection = TextSelection.collapsed(
            offset: draggedImage.start + 1,
          );
        }
        await tester.pump();
        expect(
          find.byType(ComposerImageGalleryPreview),
          findsOneWidget,
          reason: 'reordering must not expose the gallery Markdown',
        );
      }

      await drag.up();
      await tester.pumpAndSettle();

      expect(
        parseComposerImageGalleries(
          composer.text.text,
        ).single.images.map((image) => image.url),
        ['upload://two', 'upload://three', 'upload://one'],
      );
    });

    testWidgets('a cancelled gallery reorder keeps the gallery projected', (
      tester,
    ) async {
      final composer = ComposerController(
        _target,
        resolveUploadUrls: (_) async => const {},
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text =
          '[grid]\n'
          '![one](upload://one)\n'
          '![two](upload://two)\n'
          '[/grid]';

      await _pumpPanel(tester, shell, composer);
      await tester.pumpAndSettle();

      final source = composer.text.text;
      final first = tester.getCenter(
        find.byType(ComposerImageGalleryTile).first,
      );
      final outsideTarget = tester.getCenter(
        find.byType(ComposerImageGalleryControl),
      );
      final drag = await tester.startGesture(
        first,
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveTo(outsideTarget);
      final draggedImage = composer.text.galleryBlocks.single.images.first;
      composer.text.selection = TextSelection.collapsed(
        offset: draggedImage.start + 1,
      );
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle();

      expect(composer.text.text, source);
      expect(find.byType(ComposerImageGalleryPreview), findsOneWidget);
    });

    testWidgets('a gallery can import multiple standalone draft images', (
      tester,
    ) async {
      final composer = ComposerController(
        _target,
        resolveUploadUrls: (_) async => const {},
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text =
          '![outside one](upload://outside-one)\n'
          '![outside two](upload://outside-two)\n'
          '[grid]\n'
          '![inside](upload://inside)\n'
          '[/grid]';
      composer.text.selection = TextSelection.collapsed(
        offset: parseComposerImageGalleries(composer.text.text).single.end,
      );
      await _pumpPanel(tester, shell, composer);
      await tester.pumpAndSettle();

      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Add images to gallery'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add existing draft images'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DCheckbox).at(0));
      await tester.tap(find.byType(DCheckbox).at(1));
      await tester.pump();
      await tester.tap(find.text('Add selected'));
      await tester.pumpAndSettle();

      final gallery = parseComposerImageGalleries(composer.text.text).single;
      expect(gallery.images.map((image) => image.url), [
        'upload://inside',
        'upload://outside-one',
        'upload://outside-two',
      ]);
      expect(composer.standaloneImages, isEmpty);
    });

    testWidgets('removing a gallery keeps its images in order', (tester) async {
      final composer = ComposerController(
        _target,
        resolveUploadUrls: (_) async => const {},
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text =
          '[grid]\n'
          '![one](upload://one)\n'
          '![two](upload://two)\n'
          '[/grid]';
      composer.text.selection = TextSelection.collapsed(
        offset: composer.text.galleryBlocks.single.end,
      );
      await _pumpPanel(tester, shell, composer);
      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      await tester.tap(find.byTooltip('Remove gallery, keep images'));
      await tester.pump();

      expect(composer.text.galleryBlocks, isEmpty);
      expect(composer.text.imageBlocks.map((image) => image.url), [
        'upload://one',
        'upload://two',
      ]);
      expect(composer.text.text, isNot(contains('[grid')));
    });

    testWidgets('gallery controls survive changes while its picker is open', (
      tester,
    ) async {
      final picker = Completer<List<ComposerUploadFile>>();
      final calls = <_PanelUploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: (file, {required onProgress, required abortTrigger}) {
          final call = _PanelUploadCall(onProgress);
          calls.add(call);
          return call.result.future;
        },
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text =
          '[grid]\n'
          '![inside](upload://inside)\n'
          '[/grid]';
      composer.text.selection = TextSelection.collapsed(
        offset: composer.text.galleryBlocks.single.end,
      );
      await _pumpPanel(
        tester,
        shell,
        composer,
        pickImages: () => picker.future,
      );
      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      await tester.tap(find.byTooltip('Add images to gallery'));
      await tester.pumpAndSettle();
      final editorField = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.controller == composer.text,
      );
      final fieldBeforePicker = tester.widget<TextField>(editorField);
      await tester.tap(find.text('Upload new images'));
      await tester.pump();
      expect(
        tester.widget<TextField>(editorField),
        same(fieldBeforePicker),
        reason: 'picker progress should rebuild only the media overlay',
      );

      final captured = composer.text.galleryBlocks.single;
      composer.setGalleryMode(captured, ComposerGalleryMode.carousel);
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<DToggle>(
              find.descendant(
                of: find.byTooltip('Carousel gallery mode'),
                matching: find.byType(DToggle),
              ),
            )
            .pressed,
        true,
      );

      picker.complete([_file]);
      await tester.pump();
      expect(calls, hasLength(1));
      calls.single.result.complete(
        const ComposerUploadResult(
          id: 73,
          originalFilename: 'photo.png',
          shortUrl: 'upload://picked',
          url: 'https://meta.discourse.org/uploads/picked.png',
          width: 640,
          height: 480,
        ),
      );
      await tester.pump();
      await tester.pump();

      final gallery = composer.text.galleryBlocks.single;
      expect(gallery.mode, ComposerGalleryMode.carousel);
      expect(gallery.images.map((image) => image.url), [
        'upload://inside',
        'upload://picked',
      ]);
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsOneWidget,
      );
    });

    testWidgets(
      'a late gallery picker cannot upload into a replacement composer',
      (tester) async {
        final picker = Completer<List<ComposerUploadFile>>();
        final originalCalls = <_PanelUploadCall>[];
        final replacementCalls = <_PanelUploadCall>[];
        final original = ComposerController(
          _target,
          imageUploader: (file, {required onProgress, required abortTrigger}) {
            final call = _PanelUploadCall(onProgress);
            originalCalls.add(call);
            return call.result.future;
          },
        )..text.text = '[grid]\n![inside](upload://inside)\n[/grid]';
        final replacement = ComposerController(
          _target,
          imageUploader: (file, {required onProgress, required abortTrigger}) {
            final call = _PanelUploadCall(onProgress);
            replacementCalls.add(call);
            return call.result.future;
          },
        )..text.text = 'Replacement draft';
        final shell = await _shell();
        addTearDown(original.dispose);
        addTearDown(replacement.dispose);
        addTearDown(shell.dispose);
        original.text.selection = TextSelection.collapsed(
          offset: original.text.galleryBlocks.single.end,
        );
        await _pumpPanel(
          tester,
          shell,
          original,
          pickImages: () => picker.future,
        );
        original.focus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        await tester.tap(find.byTooltip('Add images to gallery'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Upload new images'));
        await tester.pump();
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is DButton &&
                widget.tooltip == 'Add images to gallery' &&
                widget.onPressed == null,
          ),
          findsOneWidget,
        );

        await _pumpPanel(tester, shell, replacement);
        picker.complete([_file]);
        await tester.pump();

        expect(originalCalls, isEmpty);
        expect(replacementCalls, isEmpty);
        expect(replacement.text.text, 'Replacement draft');
        expect(
          find.byKey(const ValueKey('composer-gallery-toolbar')),
          findsNothing,
        );
      },
    );

    for (final source in [
      '![image](upload://image)',
      '[grid]\n![image](upload://image)\n[/grid]',
    ]) {
      for (final prefix in ['', 'Before\n']) {
        testWidgets('Enter inserts a line before selected $prefix$source', (
          tester,
        ) async {
          final composer = ComposerController(
            _target,
            resolveUploadUrls: (_) async => const {},
          );
          final shell = await _InteractionTrackingShellController.create();
          addTearDown(composer.dispose);
          addTearDown(shell.dispose);
          composer.text.value = TextEditingValue(
            text: '$prefix$source',
            selection: TextSelection.collapsed(
              offset: prefix.length + source.length,
            ),
          );
          await _pumpPanel(tester, shell, composer);
          composer.focus.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          // Enter starts a separated paragraph before the selected component.
          expect(composer.text.text, '$prefix\n\n$source');
          expect(
            composer.text.selection,
            TextSelection.collapsed(offset: prefix.length),
          );
          expect(composer.text.keyboardSelectedProjection, isNull);
          expect(
            find.byKey(const ValueKey('composer-gallery-toolbar')),
            findsNothing,
          );
          expect(shell.submitCalls, 0);
          composer.draftSettled();
        });
      }
    }

    testWidgets('Ctrl+Enter submits while gallery controls are selected', (
      tester,
    ) async {
      final composer = ComposerController(
        _target,
        onSaveDraft: (save) async => save.sequence + 1,
        resolveUploadUrls: (_) async => const {},
      );
      final shell = await _InteractionTrackingShellController.create();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text =
          '[grid]\n'
          '![inside](upload://inside)\n'
          '[/grid]';
      composer.text.selection = TextSelection.collapsed(
        offset: composer.text.galleryBlocks.single.end,
      );
      await _pumpPanel(tester, shell, composer);
      composer.focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsOneWidget,
      );

      final selectedValue = composer.text.value;
      final caret = selectedValue.selection.extentOffset;
      tester.testTextInput.updateEditingValue(
        selectedValue.copyWith(
          text: selectedValue.text.replaceRange(caret, caret, 'pasted text'),
          selection: TextSelection.collapsed(
            offset: caret + 'pasted text'.length,
          ),
        ),
      );
      await tester.pump();
      expect(composer.text.value, selectedValue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(shell.submitCalls, 1);
      expect(composer.text.galleryBlocks, hasLength(1));

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsNothing,
      );
      expect(shell.closeCalls, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(shell.closeCalls, 1);
      composer.draftSettled();
    });

    testWidgets('dropping an image over a gallery appends it there', (
      tester,
    ) async {
      final calls = <_PanelUploadCall>[];
      final composer = ComposerController(
        _target,
        imageUploader: (file, {required onProgress, required abortTrigger}) {
          final call = _PanelUploadCall(onProgress);
          calls.add(call);
          return call.result.future;
        },
      );
      final shell = await _shell();
      addTearDown(composer.dispose);
      addTearDown(shell.dispose);
      composer.text.text =
          '[grid]\n'
          '![inside](upload://inside)\n'
          '[/grid]';
      await _pumpPanel(tester, shell, composer);
      await tester.pumpAndSettle();

      final position = tester
          .getRect(find.byType(ComposerImageGalleryControl))
          .center;
      final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
      dropTarget.onDragEntered!(
        DropEventDetails(localPosition: position, globalPosition: position),
      );
      await tester.pump();
      expect(find.text('Drop images into this gallery'), findsNothing);
      expect(find.byType(DDropIndicator), findsNothing);

      dropTarget.onDragDone!(
        DropDoneDetails(
          files: [
            DropItemFile(
              '/tmp/dropped.png',
              bytes: Uint8List.fromList(const [1, 2, 3]),
            ),
          ],
          localPosition: position,
          globalPosition: position,
        ),
      );
      await tester.pump();
      expect(calls, hasLength(1));
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ComposerImageGalleryPreview>(
              find.byType(ComposerImageGalleryPreview),
            )
            .highlighted,
        isTrue,
      );
      expect(
        composer.text.selection.extentOffset,
        composer.text.galleryBlocks.single.end,
      );
      calls.single.result.complete(
        const ComposerUploadResult(
          id: 74,
          originalFilename: 'dropped.png',
          shortUrl: 'upload://dropped',
          url: 'https://meta.discourse.org/uploads/dropped.png',
          width: 640,
          height: 480,
        ),
      );
      await tester.pump();

      expect(
        composer.text.galleryBlocks.single.images.map((image) => image.url),
        ['upload://inside', 'upload://dropped'],
      );
      expect(composer.standaloneImages, isEmpty);
      expect(
        find.byKey(const ValueKey('composer-gallery-toolbar')),
        findsOneWidget,
      );
      expect(
        composer.text.selection.extentOffset,
        composer.text.galleryBlocks.single.end,
      );
    });
  });
}

Future<ShellController> _shell() async {
  final shell = ShellController(
    instanceStore: FakeInstanceStore(),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    trackers: FakeSiteTracker.reset(),
  );
  await shell.load();
  return shell;
}

Future<void> _pumpPanel(
  WidgetTester tester,
  ShellController shell,
  ComposerController composer, {
  double? height,
  ComposerFilePicker pickFiles = _cancelImagePick,
  ComposerImagePicker? pickImages = _cancelImagePick,
  ComposerClipboardFileReader readClipboardFiles = readComposerClipboardFiles,
}) => tester.pumpWidget(
  MaterialApp(
    theme: AppTheme.dark,
    home: ShellScope(
      controller: shell,
      child: Scaffold(
        body: ComposerPanel(
          composer: composer,
          height: height ?? 500,
          pickFiles: pickFiles,
          pickImages: pickImages,
          readClipboardFiles: readClipboardFiles,
        ),
      ),
    ),
  ),
);

Future<List<ComposerUploadFile>> _cancelImagePick() async => const [];

/// Answers the pasteboard plugin's channel and records each method it is asked.
List<String> _mockPasteboardPlugin(
  WidgetTester tester, {
  required List<String> files,
  Uint8List? image,
}) {
  const channel = MethodChannel('pasteboard');
  final messenger = tester.binding.defaultBinaryMessenger;
  final calls = <String>[];
  messenger.setMockMethodCallHandler(channel, (call) async {
    calls.add(call.method);
    return switch (call.method) {
      'files' => files,
      'image' => image,
      _ => fail('Unexpected pasteboard method: ${call.method}'),
    };
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return calls;
}

/// Answers the engine's plain-text clipboard queries and records each asked.
List<String> _mockClipboardText(WidgetTester tester, String? text) {
  final messenger = tester.binding.defaultBinaryMessenger;
  final calls = <String>[];
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (!call.method.startsWith('Clipboard.')) return null;
    calls.add(call.method);
    return switch (call.method) {
      'Clipboard.hasStrings' => {'value': text != null && text.isNotEmpty},
      'Clipboard.getData' => text == null ? null : {'text': text},
      _ => null,
    };
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return calls;
}

/// Answers the macOS runner's file-URL-only pasteboard channel.
List<String> _mockPasteboardFileUrls(WidgetTester tester, List<String> paths) {
  const channel = MethodChannel('org.discourse.native/pasteboard');
  final messenger = tester.binding.defaultBinaryMessenger;
  final calls = <String>[];
  messenger.setMockMethodCallHandler(channel, (call) async {
    calls.add(call.method);
    return switch (call.method) {
      'fileURLPaths' => paths,
      _ => fail('Unexpected pasteboard method: ${call.method}'),
    };
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return calls;
}

Future<void> _pasteShortcut(WidgetTester tester) async {
  final modifier = switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => LogicalKeyboardKey.metaLeft,
    _ => LogicalKeyboardKey.controlLeft,
  };
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

EditableText _composerEditable(WidgetTester tester) =>
    tester.widget<EditableText>(
      find.descendant(
        of: find.byType(ComposerEditor),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is EditableText &&
              widget.controller is MarkdownEditingController,
        ),
      ),
    );

const _target = ComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 7,
  slug: 'a-topic',
  topicTitle: 'A topic',
);

final _file = ComposerUploadFile(
  name: 'photo.png',
  length: () => Future.value(3),
  openRead: () => Stream.value([1, 2, 3]),
);

final class _RecordingImagePicker extends images.ImagePickerPlatform {
  images.MultiImagePickerOptions? options;

  @override
  Future<List<images.XFile>> getMultiImageWithOptions({
    images.MultiImagePickerOptions options =
        const images.MultiImagePickerOptions(),
  }) async {
    this.options = options;
    return const [];
  }
}

class _PanelUploadCall {
  _PanelUploadCall(this.onProgress);

  final void Function(double) onProgress;
  final Completer<ComposerUploadResult> result = Completer();
}

final class _InteractionTrackingShellController extends ShellController {
  _InteractionTrackingShellController()
    : super(
        instanceStore: FakeInstanceStore(),
        api: FakeDiscourseApi(),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );

  int closeCalls = 0;
  int submitCalls = 0;

  static Future<_InteractionTrackingShellController> create() async {
    final shell = _InteractionTrackingShellController();
    await shell.load();
    return shell;
  }

  @override
  void closeComposer({ComposerController? composer}) => closeCalls++;

  @override
  bool hideComposerForClose(ComposerController composer) =>
      composer.beginClose();

  @override
  Future<bool> finishComposerDraftRestore(ComposerController composer) async =>
      true;

  @override
  Future<void> submitComposer({
    ComposerController? composer,
    void Function(String)? onPreparationNotice,
  }) async => submitCalls++;
}
