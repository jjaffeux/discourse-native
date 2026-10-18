import 'dart:async';

import 'package:discourse_native/src/data/site_lifecycle.dart';
import 'package:discourse_native/src/shell/reader_media_activity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hidden attachment suppresses initialization synchronously', () {
    final activity = ReaderMediaActivity();
    addTearDown(activity.dispose);
    activity.present(
      foreground: true,
      rowVisible: false,
      geometryVisible: true,
    );
    final endpoint = _Endpoint();
    final attachment = activity.attach(source: 'first', endpoint: endpoint);
    expect(endpoint.visibility, [false]);
    expect(attachment.mayPlay, isFalse);
    activity.present(foreground: true, rowVisible: true, geometryVisible: true);
    expect(activity.claimPlay(attachment), isTrue);
    expect(endpoint.visibility.where((visible) => !visible), hasLength(1));
  });

  test('a pending visibility grant cannot override a newer hide', () async {
    final activity = ReaderMediaActivity();
    addTearDown(activity.dispose);
    final gate = Completer<void>();
    final endpoint = _Endpoint()..nextCompletion = gate.future;
    activity.attach(source: 'first', endpoint: endpoint);
    activity.present(
      foreground: true,
      rowVisible: false,
      geometryVisible: true,
    );
    activity.present(foreground: true, rowVisible: true, geometryVisible: true);
    activity.present(
      foreground: false,
      rowVisible: true,
      geometryVisible: true,
    );
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(endpoint.visibility, [true, false, false, false]);
  });

  test('late hidden playback is paused again after a pending pause', () async {
    final activity = ReaderMediaActivity();
    addTearDown(activity.dispose);
    final endpoint = _Endpoint();
    final attachment = activity.attach(source: 'first', endpoint: endpoint);
    await Future<void>.delayed(Duration.zero);
    final gate = Completer<void>();
    endpoint.nextCompletion = gate.future;
    activity.present(
      foreground: true,
      rowVisible: false,
      geometryVisible: true,
    );
    activity.playbackChanged(attachment, true);
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(endpoint.visibility, [true, false, false]);
  });

  test('retirement revokes setup callbacks and queued visibility', () async {
    final activity = ReaderMediaActivity();
    addTearDown(activity.dispose);
    final gate = Completer<void>();
    final first = _Endpoint()..nextCompletion = gate.future;
    final old = activity.attach(source: 'first', endpoint: first);
    activity.present(
      foreground: true,
      rowVisible: false,
      geometryVisible: true,
    );
    final replacement = _Endpoint();
    final current = activity.attach(source: 'second', endpoint: replacement);
    activity.refresh(old);
    activity.playbackChanged(old, true);
    gate.complete();
    await Future<void>.delayed(Duration.zero);
    expect(old.isCurrent, isFalse);
    expect(current.isCurrent, isTrue);
    expect(first.visibility, [true]);
    expect(first.retirements, 1);
    expect(replacement.visibility, [false]);
    activity.retire();
    activity.retire();
    expect(replacement.retirements, 1);
  });

  test('fullscreen permission belongs to one source and its visible route', () {
    final activity = ReaderMediaActivity();
    addTearDown(activity.dispose);
    final old = activity.attach(source: 'first', endpoint: _Endpoint());
    activity.fullscreen(old, visible: true);
    activity.present(
      foreground: true,
      rowVisible: false,
      geometryVisible: false,
    );
    expect(old.mayPlay, isTrue);
    activity.fullscreen(old, visible: false);
    expect(old.mayPlay, isFalse);
    activity.fullscreen(old, visible: true);
    final current = activity.attach(source: 'second', endpoint: _Endpoint());
    expect(current.mayPlay, isFalse);
    activity.fullscreen(old, visible: true);
    expect(current.mayPlay, isFalse);
    activity.fullscreen(current, visible: true);
    activity.present(
      foreground: false,
      rowVisible: false,
      geometryVisible: false,
    );
    expect(current.mayPlay, isFalse);
    activity.present(
      foreground: true,
      rowVisible: false,
      geometryVisible: false,
    );
    activity.endFullscreen(current);
    expect(current.mayPlay, isFalse);
  });

  test('a retired account cannot authorize late setup or manual playback', () {
    final lifecycle = SiteLifecycle();
    final activity = ReaderMediaActivity();
    addTearDown(activity.dispose);
    final endpoint = _Endpoint();
    final attachment = activity.attach(
      source: 'first',
      endpoint: endpoint,
      account: lifecycle.capture('https://forum.test'),
    );
    lifecycle.invalidate('https://forum.test');
    expect(attachment.isCurrent, isFalse);
    expect(activity.claimPlay(attachment), isFalse);
    activity.refresh(attachment);
    activity.present(foreground: true, rowVisible: true, geometryVisible: true);
    expect(endpoint.retirements, 1);
  });

  test('only uploaded video participants interrupt one another', () async {
    final first = ReaderMediaActivity();
    final second = ReaderMediaActivity();
    final independent = ReaderMediaActivity();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    addTearDown(independent.dispose);
    final firstEndpoint = _Endpoint();
    final firstVideo = first.attach(
      source: 'video one',
      endpoint: firstEndpoint,
      exclusiveVideo: true,
    );
    first.claimPlay(firstVideo);
    final audioEndpoint = _Endpoint();
    final audio = independent.attach(source: 'audio', endpoint: audioEndpoint);
    independent.claimPlay(audio);
    final nextVideo = second.attach(
      source: 'video two',
      endpoint: _Endpoint(),
      exclusiveVideo: true,
    );
    second.claimPlay(nextVideo);
    await Future<void>.delayed(Duration.zero);
    expect(firstEndpoint.visibility, [true, false]);
    expect(audioEndpoint.visibility, [true]);
  });
}

final class _Endpoint implements ReaderMediaEndpoint {
  final visibility = <bool>[];
  Future<void>? nextCompletion;
  int retirements = 0;

  @override
  Future<void> setPlaybackVisible(bool visible) {
    visibility.add(visible);
    final completion = nextCompletion;
    nextCompletion = null;
    return completion ?? Future<void>.value();
  }

  @override
  void retire() => retirements++;
}
