import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/shell/composer/controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preparation owns an attempt before outgoing facts are frozen', () {
    final composer = ComposerController(_target);
    addTearDown(() {
      if (!composer.isDisposed) composer.dispose();
    });
    composer.text.text = 'Ready to send';
    final attempt = Object();

    composer.beginSubmit(attempt: attempt);

    expect(composer.state, ComposerState.submitting);
    expect(composer.ownsSubmission(attempt), isTrue);
    expect(composer.submission, isNull);
    expect(composer.isEditing, isFalse);
    expect(composer.canSubmit, isFalse);
    expect(composer.beginDiscard(), isNull);

    composer.failed(const WriteException(WriteFailure.conflict));

    expect(composer.state, ComposerState.editing);
    expect(composer.ownsSubmission(attempt), isFalse);
    expect(composer.submission, isNull);
    expect(composer.canSubmit, isTrue);
  });

  test(
    'unresolved text stays editable while the original facts are retained',
    () {
      final composer = ComposerController(_target);
      addTearDown(() {
        if (!composer.isDisposed) composer.dispose();
      });
      composer.text.text = 'Original sent text';
      final sent = _Sent(Object(), composer.raw);
      composer.beginSubmit(attempt: sent.attempt);
      composer.retainSubmission(sent);
      composer.checking();
      expect(composer.state, ComposerState.checking);
      expect(composer.isEditing, isFalse);
      expect(composer.beginDiscard(), isNull);

      composer.unresolved();
      composer.text.text = 'Edited after the response was lost';
      composer.retarget(replyToPostNumber: 9, replyToUsername: 'other');

      expect(composer.isEditing, isTrue);
      expect(composer.canSubmit, isFalse);
      expect(composer.canRecheck, isTrue);
      expect(composer.submission, same(sent));
      expect(sent.raw, 'Original sent text');
      expect(composer.target.replyToPostNumber, 9);
      composer.checking();
      expect(composer.submission, same(sent));

      composer.checkedNotPosted(const WriteException(WriteFailure.unreachable));

      expect(composer.submission, isNull);
      expect(composer.ownsSubmission(sent.attempt), isFalse);
      expect(composer.canRecheck, isFalse);
      expect(composer.canSubmit, isTrue);
      expect(composer.raw, 'Edited after the response was lost');
    },
  );

  for (final preparing in [false, true]) {
    test(
      'checking and unresolved require sent facts, preparing=$preparing',
      () {
        final composer = ComposerController(_target);
        addTearDown(composer.dispose);
        if (preparing) composer.beginSubmit();
        var notifications = 0;
        composer.addListener(() => notifications++);

        composer.checking();
        composer.unresolved();

        expect(
          composer.state,
          preparing ? ComposerState.submitting : ComposerState.editing,
        );
        expect(composer.submission, isNull);
        expect(composer.canRecheck, isFalse);
        expect(notifications, 0);
      },
    );
  }

  test(
    'retention freezes facts once across sending, checking and unresolved',
    () {
      final composer = ComposerController(_target);
      addTearDown(composer.dispose);
      final attempt = Object();
      final sent = _Sent(attempt, 'Original');
      final replacement = _Sent(attempt, 'Replacement');
      composer.beginSubmit(attempt: attempt);
      composer.retainSubmission(const _Sent(Object(), 'Wrong attempt'));
      expect(composer.submission, isNull);
      composer.retainSubmission(sent);

      for (final transition in [
        () {},
        composer.checking,
        composer.unresolved,
      ]) {
        transition();
        composer.retainSubmission(replacement);
        expect(composer.submission, same(sent));
        expect(composer.ownsSubmission(attempt), isTrue);
      }
    },
  );

  test('synchronous checking listener can retire the sent attempt', () {
    final composer = ComposerController(_target);
    addTearDown(composer.dispose);
    const sent = _Sent(Object(), 'Original');
    composer.beginSubmit(attempt: sent.attempt);
    composer.retainSubmission(sent);
    composer.addListener(() {
      if (composer.state == ComposerState.checking) composer.clearDocument();
    });

    composer.checking();
    composer.unresolved();
    composer.retainSubmission(sent);

    expect(composer.state, ComposerState.editing);
    expect(composer.ownsSubmission(sent.attempt), isFalse);
    expect(composer.submission, isNull);
    expect(composer.canRecheck, isFalse);
  });

  test('a retired attempt cannot install facts into a replacement attempt', () {
    final composer = ComposerController(_target);
    addTearDown(() {
      if (!composer.isDisposed) composer.dispose();
    });
    const old = _Sent(Object(), 'Old');
    composer.beginSubmit(attempt: old.attempt);
    composer.clearDocument();
    composer.text.text = 'Replacement';
    final next = _Sent(Object(), composer.raw);
    composer.beginSubmit(attempt: next.attempt);

    composer.retainSubmission(old);
    expect(composer.submission, isNull);
    expect(composer.ownsSubmission(old.attempt), isFalse);
    expect(composer.ownsSubmission(next.attempt), isTrue);
    composer.retainSubmission(next);
    expect(composer.submission, same(next));

    composer.dispose();
    composer.retainSubmission(old);
    expect(composer.submission, isNull);
    expect(composer.ownsSubmission(next.attempt), isFalse);
  });
}

final class _Sent implements ComposerSubmission {
  const _Sent(this.attempt, this.raw);

  @override
  final Object attempt;
  final String raw;
}

const _target = ReplyComposerTarget(
  siteUrl: 'https://meta.discourse.org',
  topicId: 7,
  slug: 'topic',
  privateMessageTopic: false,
  topicTitle: 'Topic',
);
