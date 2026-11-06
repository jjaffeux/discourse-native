# Local search results during network refresh

Searchable controls publish current, eligible local matches before waiting for
server discovery. A response enriches only the query and account session that
requested it. Authoring permissions, disabled choices, creation limits, and
write checks remain enforced by their existing owners.

| Surface | Immediate results | Server enrichment |
| --- | --- | --- |
| Topic-list tag filters | Known unscoped forum tags | Tags and tag groups publish independently |
| Category selectors | Eligible categories supplied by the caller | Additional categories and refreshed metadata |
| Global-search categories | Matching choices from the current session | Authoritative results replace the preview and retain pagination |
| Composer emoji | Canonical catalog matches, independent of mention slots | Optional localized aliases refresh the current query |
| Start chatting | Matching loaded channels | Current server results retain authority over disabled choices |
| Assignment | Assignees already supplied by the target's server suggestions or searches | New matches are checked by the server; obsolete responses are discarded |

Scoped tag searches and unknown authoring choices continue to require their
server-provided eligibility. Discovery stays debounced, and tag enrichment
retains its bounded queue. New assignment queries run independently of obsolete
lookups. Optional tag groups and emoji aliases do not block primary matches.

## Verification

The regression tests hold old and current API responses unresolved, then
exercise visible local matches and selection through the existing Native
controls. They also cover late responses, account retirement, failed optional
enrichment, category permissions, disabled chat replacements, and assignment
save feedback while a search is still pending.

Category coverage includes keyboard and pointer selection, duplicate-free
enrichment, account-cache invalidation, and composer create permissions.
Emoji coverage saturates mention requests and holds locale aliases separately.
Tag coverage includes slow tag groups and parent rebuilds that occur after
partial results arrive. Plugin coverage exercises the actual chat and
assignment widgets alongside their session boundaries.

Tests run by explicit related file paths. Existing mobile keyboard-layout and
sheet Close-tooltip assertions were reproduced on unchanged code and kept
separate from the network-response fixes.

The new focused regression files can be run together:

```sh
flutter test test/topic_category_local_search_test.dart \
  test/topic_filter_tag_latency_test.dart \
  test/topic_tag_local_refresh_test.dart \
  test/composer_emoji_latency_test.dart
```

Existing global-search, composer, chat, assignment, picker-lifecycle, and
account-boundary suites pin the surrounding behavior.

The integrated run passed 843 tests across 28 related files. One optional
performance trace was skipped. Fifteen existing mobile-presentation assertions
were excluded after reproducing them on unchanged code: eight picker keyboard
geometry cases, four chat keyboard geometry cases, and three assignment
Close-tooltip cases. Static analysis of every changed Dart file was clean.

All fifteen presentation failures were resolved in a follow-up. Keyboard tests
now check visible bodies, lists, and inputs above the keyboard while the sheet
surface continues behind it. Exact field and footer metrics follow the current
Native presets. Grabber-only shell headers again omit Close, while nested Back
and non-draggable Close actions remain covered. All 150 tests in the six
affected suites passed without exclusions, as did 208 Native sheet contract
tests. Static analysis and independent review were clean.
