import 'package:discourse_native/src/data/discourse_api_contracts.dart';
import 'package:flutter_test/flutter_test.dart';

const _fallback = 'fallback sentence';

void main() {
  group('failureText', () {
    test('a write failure speaks in the site\'s own words', () {
      expect(
        failureText(
          const WriteException(
            WriteFailure.validation,
            errors: ['Column is full', 'Try another'],
            statusCode: 422,
          ),
          fallback: _fallback,
        ),
        'Column is full\nTry another',
      );
    });

    test('a write failure with no words speaks for its category', () {
      for (final failure in WriteFailure.values) {
        final error = WriteException(failure);
        expect(failureText(error, fallback: _fallback), error.message);
        expect(failureText(error, fallback: _fallback), isNot(_fallback));
      }
    });

    test('a refused write never shows its type name or fields', () {
      final text = failureText(
        const WriteException(WriteFailure.rateLimited, statusCode: 429),
        fallback: _fallback,
      );
      expect(text, isNot(contains('WriteException')));
      expect(text, isNot(contains('statusCode')));
    });

    test('a site that never answered is named as unreachable', () {
      expect(
        failureText(
          const SiteLookupException(
            SiteLookupFailure.unreachable,
            'https://forum.example',
          ),
          fallback: _fallback,
        ),
        "Couldn't reach https://forum.example.",
      );
    });

    test('a site that answered with a status is not called unreachable', () {
      final shown = {
        for (final status in [404, 410, 429, 500, 502, 503])
          status: failureText(
            SiteLookupException(
              SiteLookupFailure.unreachable,
              'https://forum.example',
              statusCode: status,
            ),
            fallback: _fallback,
          ),
      };
      expect(shown, {
        404: _fallback,
        410: _fallback,
        429: _fallback,
        500: _fallback,
        502: _fallback,
        503: _fallback,
      });
    });

    test('a lookup without a status keeps its message', () {
      const error = SiteLookupException(
        SiteLookupFailure.notDiscourse,
        'https://forum.example',
      );
      expect(failureText(error, fallback: _fallback), error.message);
      expect(
        failureText(error, fallback: _fallback),
        contains('forum.example'),
      );
    });

    test('a 401 or 403 refusal is not called a missing forum', () {
      for (final status in [401, 403]) {
        final text = failureText(
          SiteLookupException(
            SiteLookupFailure.notDiscourse,
            'https://forum.example',
            statusCode: status,
          ),
          fallback: _fallback,
        );
        expect(text, "This account can't access that.");
      }
      expect(
        failureText(
          const ApiKeyRejectedException('https://forum.example'),
          fallback: _fallback,
        ),
        "This account can't access that.",
      );
    });

    test('a 404 answer to a discovery read still says not a forum', () {
      final text = failureText(
        const SiteLookupException(
          SiteLookupFailure.notDiscourse,
          'https://forum.example',
          statusCode: 404,
        ),
        fallback: _fallback,
      );
      expect(text, contains('is not a Discourse forum'));
    });

    test('a basic-auth challenge keeps its own message', () {
      final error = HttpBasicAuthenticationRequired(
        Uri.parse('https://forum.example/c/a'),
      );
      expect(failureText(error, fallback: _fallback), error.message);
    });

    test('anything else is replaced by the fallback', () {
      for (final error in <Object>[
        const FormatException('Invalid board response'),
        StateError('closed'),
        Exception('boom'),
        TypeError(),
        'a string',
      ]) {
        expect(failureText(error, fallback: _fallback), _fallback);
      }
    });
  });
}
