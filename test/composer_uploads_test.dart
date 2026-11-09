import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';
import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/models/composer_upload.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/plugin_api/composer_target.dart';
import 'package:discourse_native/src/shell/composer/composer_uploads.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _site = 'https://meta.discourse.org';
const _result = ComposerUploadResult(
  id: 1,
  originalFilename: 'a.pdf',
  shortUrl: 'upload://a.pdf',
  url: '/uploads/a.pdf',
);
final _file = ComposerUploadFile(
  name: 'a.pdf',
  length: () async => 1,
  openRead: () => const Stream.empty(),
);

void main() {
  test('a file is sent for the account that asked', () async {
    final h = _Harness();

    final result = await h.upload();

    expect(result.id, 1);
    expect(h.api.composerUploads.single.filename, 'a.pdf');
    expect(h.api.composerUploads.single.siteUrl, _site);
  });

  test('a disposed composer reads no credential', () async {
    final h = _Harness()..disposed = true;

    await expectLater(h.upload(), _throwsMessage(appL10n.uploadCancelled));

    expect(h.credentials.reads, 0);
    expect(h.api.composerUploads, isEmpty);
  });

  test('an account retired during the key read sends nothing', () async {
    final credentials = _GatedCredentials();
    final h = _Harness(credentials: credentials);

    final upload = h.upload();
    await pumpEventQueue();
    h.lifecycle.invalidate(_site);
    credentials.pending.complete('key');

    await expectLater(upload, _throwsMessage(appL10n.uploadCancelled));
    expect(h.api.composerUploads, isEmpty);
  });

  test('disposal during the key read sends nothing', () async {
    final credentials = _GatedCredentials();
    final h = _Harness(credentials: credentials);

    final upload = h.upload();
    await pumpEventQueue();
    h.disposed = true;
    credentials.pending.complete('key');

    await expectLater(upload, _throwsMessage(appL10n.uploadCancelled));
    expect(h.api.composerUploads, isEmpty);
  });

  test('a signed-out account is refused with the forbidden message', () async {
    final h = _Harness(credentials: _CountingCredentials());

    await expectLater(
      h.upload(),
      _throwsMessage(const WriteException(WriteFailure.forbidden).message),
    );
    expect(h.api.composerUploads, isEmpty);
  });

  test('an unreadable key is refused with the unreachable message', () async {
    final h = _Harness(
      credentials: _CountingCredentials()..failure = StateError('locked'),
    );

    await expectLater(
      h.upload(),
      _throwsMessage(const WriteException(WriteFailure.unreachable).message),
    );
    expect(h.api.composerUploads, isEmpty);
  });

  test('the size limit reads the configuration at send time', () async {
    final h = _Harness()..current = const SiteConfig(maxAttachmentSizeKb: 7);

    await h.upload();

    expect(h.api.composerUploads.single.sizeLimit?.maxBytes, 7 * 1024);
  });

  test('a reply inside a message uploads as private', () async {
    final h = _Harness(target: _reply(privateMessageTopic: true));

    await h.upload();

    expect(h.api.composerUploads.single.forPrivateMessage, isTrue);
  });

  test('a public reply does not upload as private', () async {
    final h = _Harness(target: _reply(privateMessageTopic: false));

    await h.upload();

    expect(h.api.composerUploads.single.forPrivateMessage, isFalse);
  });

  test('a staff member may attach any file only inside a message', () {
    const config = SiteConfig(allowStaffToUploadAnyFileInPm: true);
    final inMessage = _Harness(
      target: _reply(privateMessageTopic: true),
      composerConfig: config,
    )..staff = true;
    final inPublic = _Harness(
      target: _reply(privateMessageTopic: false),
      composerConfig: config,
    )..staff = true;

    expect(inMessage.uploads.canUploadFile('tool.exe'), isTrue);
    expect(inPublic.uploads.canUploadFile('tool.exe'), isFalse);
  });

  test('admission reads the configuration the composer opened with', () {
    final h = _Harness(
      composerConfig: const SiteConfig(authorizedExtensions: ['pdf']),
    )..current = const SiteConfig(authorizedExtensions: ['zip']);

    expect(h.uploads.canUploadFile('a.pdf'), isTrue);
    expect(h.uploads.canUploadFile('a.zip'), isFalse);
  });

  test('a short url lookup answers for the current account', () async {
    final h = _Harness();

    expect(await h.uploads.resolveUrls(const ['upload://a']), const {
      'upload://a': '/uploads/a',
    });
  });

  test('a short url lookup for a retired account answers nothing', () async {
    final credentials = _GatedCredentials();
    final h = _Harness(credentials: credentials);

    final found = h.uploads.resolveUrls(const ['upload://a']);
    await pumpEventQueue();
    h.lifecycle.invalidate(_site);
    credentials.pending.complete('key');

    expect(await found, isEmpty);
    expect(h.api.urlLookups, isEmpty);
  });
}

Matcher _throwsMessage(String message) => throwsA(
  isA<ComposerUploadException>().having(
    (error) => error.message,
    'message',
    message,
  ),
);

ComposerTarget _reply({required bool privateMessageTopic}) =>
    ReplyComposerTarget(
      siteUrl: _site,
      topicTitle: 'Topic',
      topicId: 7,
      slug: 'topic',
      privateMessageTopic: privateMessageTopic,
      draftKey: 'topic_7',
    );

class _CountingCredentials extends FakeApiCredentialReader {
  Object? failure;
  int reads = 0;

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    reads++;
    if (failure case final error?) return Future.error(error);
    return super.apiKeyFor(siteUrl);
  }
}

final class _GatedCredentials extends _CountingCredentials {
  final pending = Completer<String?>();

  @override
  Future<String?> apiKeyFor(String siteUrl) {
    reads++;
    return pending.future;
  }
}

final class _Api extends FakeDiscourseApi {
  _Api() : super(composerUploadResult: _result);

  final urlLookups = <Iterable<String>>[];

  @override
  Future<Map<String, String>> lookupUploadUrls({
    required String siteUrl,
    required String apiKey,
    required Iterable<String> shortUrls,
    String? clientId,
  }) async {
    urlLookups.add(shortUrls);
    return const {'upload://a': '/uploads/a'};
  }
}

final class _Harness {
  _Harness({
    _CountingCredentials? credentials,
    ComposerTarget? target,
    SiteConfig? composerConfig,
  }) : credentials =
           credentials ?? (_CountingCredentials()..keys[_site] = 'key'),
       target = target ?? _reply(privateMessageTopic: false),
       composerConfig = composerConfig ?? const SiteConfig();

  final _CountingCredentials credentials;
  final ComposerTarget target;
  final SiteConfig composerConfig;
  final api = _Api();
  final lifecycle = SiteLifecycle();
  SiteConfig current = const SiteConfig();
  bool staff = false;
  bool disposed = false;

  late final uploads = ComposerUploads(
    target: target,
    composerConfig: composerConfig,
    api: api,
    credentials: credentials,
    lifecycle: lifecycle,
    currentConfig: () => current,
    isStaff: () => staff,
    isDisposed: () => disposed,
  );

  Future<ComposerUploadResult> upload() => uploads.upload(
    _file,
    onProgress: (_) {},
    abortTrigger: Completer<void>().future,
  );
}
