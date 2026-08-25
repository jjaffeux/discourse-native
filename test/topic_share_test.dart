import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/shell/topic_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('topic links match core including the referral suffix', () {
    expect(
      topicShareUrl(
        siteUrl: 'https://meta.discourse.org/',
        topicId: 7,
        slug: 'a-real-topic',
        username: 'Reader',
        config: const SiteConfig.unknown(),
      ),
      'https://meta.discourse.org/t/a-real-topic/7?u=reader',
    );
  });

  test('a missing slug uses core’s topic fallback', () {
    expect(
      topicShareUrl(
        siteUrl: 'https://meta.discourse.org',
        topicId: 7,
        slug: '   ',
        config: const SiteConfig.unknown(),
      ),
      'https://meta.discourse.org/t/topic/7',
    );
  });

  test('post links append the post number before a referral suffix', () {
    expect(
      postShareUrl(
        siteUrl: 'https://meta.discourse.org',
        topicId: 7,
        postNumber: 3,
        slug: 'a-real-topic',
        username: 'Reader',
        config: const SiteConfig.unknown(),
      ),
      'https://meta.discourse.org/t/a-real-topic/7/3?u=reader',
    );
    expect(
      postCanonicalUrl(
        siteUrl: 'https://meta.discourse.org',
        topicId: 7,
        postNumber: 3,
        slug: 'a-real-topic',
      ),
      'https://meta.discourse.org/t/a-real-topic/7/3',
    );
  });

  test('continuation copy is a safe Markdown backlink', () {
    expect(
      topicContinuationMarkdown(
        title: r'A [bracket] and \ slash',
        url: 'https://meta.discourse.org/t/topic/7',
      ),
      r'Continue the discussion from [A \[bracket\] and \\ slash](https://meta.discourse.org/t/topic/7)',
    );
  });
}
