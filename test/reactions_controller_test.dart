import 'dart:async';

import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/data/store.dart';
import 'package:discourse_native/src/plugins/reactions/post_reactors.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _siteUrl = 'https://meta.discourse.org';

final class _SequencedReactorsApi implements ReactionsApi {
  _SequencedReactorsApi(this.gates);

  final List<Completer<void>> gates;
  int requests = 0;

  @override
  Future<PostReactors> postReactors({
    required String siteUrl,
    required int postId,
    String? reaction,
    int limit = 30,
    String? apiKey,
    String? clientId,
  }) async {
    final request = requests++;
    await gates[request].future;
    return PostReactors(
      postId: postId,
      filter: reaction,
      total: 1,
      reactors: [
        PostReactor(
          id: request + 1,
          username: request == 0 ? 'account-a' : 'account-b',
          reaction: reaction ?? 'heart',
        ),
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an old finalizer cannot release a new session request', () async {
    final oldGate = Completer<void>();
    final newGate = Completer<void>();
    final api = _SequencedReactorsApi([oldGate, newGate]);
    final lifecycle = SiteLifecycle();
    final store = Store();
    final controller = ReactionsController(
      api: api,
      credentials: FakeApiCredentialReader(),
      store: store,
      lifecycle: lifecycle,
    );
    addTearDown(controller.dispose);

    final oldLoad = controller.load(siteUrl: _siteUrl, postId: 7);
    await Future<void>.delayed(Duration.zero);
    lifecycle.invalidate(_siteUrl);
    controller.forget(_siteUrl);

    final newLoad = controller.load(siteUrl: _siteUrl, postId: 7);
    await Future<void>.delayed(Duration.zero);
    expect(api.requests, 2);

    oldGate.complete();
    await oldLoad;
    await controller.load(siteUrl: _siteUrl, postId: 7);

    // The old request's `finally` did not remove the new request's loading
    // guard, so opening the same list again did not start a third request.
    expect(api.requests, 2);
    expect(controller.reactors(_siteUrl, 7), isNull);

    newGate.complete();
    await newLoad;

    expect(api.requests, 2);
    expect(
      controller.reactors(_siteUrl, 7)?.reactors.single.username,
      'account-b',
    );
  });

  test('forget notifies direct consumers when request state disappears', () {
    final controller = ReactionsController(
      api: _SequencedReactorsApi([Completer<void>()]),
      credentials: FakeApiCredentialReader(),
      store: Store(),
    );
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    unawaited(controller.load(siteUrl: _siteUrl, postId: 7));
    expect(notifications, 1);

    controller.forget(_siteUrl);
    expect(notifications, 2);
  });
}
