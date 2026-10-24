import 'package:discourse_native/src/shell/composer/controller.dart';

void beginTestComposerSubmission(ComposerController composer) {
  final submission = _TestComposerSubmission();
  composer.beginSubmit(attempt: submission.attempt);
  composer.retainSubmission(submission);
}

final class _TestComposerSubmission implements ComposerSubmission {
  @override
  final Object attempt = Object();
}
