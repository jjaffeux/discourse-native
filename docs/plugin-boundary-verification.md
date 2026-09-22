# Plugin boundary verification — 2026-09-22

Source revision: `6bb4bebf7`. Comparison baseline: `c42011820`.

## Ownership audit

- Chat owns its channel-list preference model, preference wire codec, search
  implementation, cooking profile, icon aliases and direct-message shortcut.
- Assign owns its persisted display preference and search filters. Poll, Solved
  and Topic Voting register their own search filters and orders.
- Mobile navigation, preference editors, draft presentation, composer labels,
  compact emoji handling, notification sections and icon resolution consume
  registered contributions instead of recognizing bundled feature identities.
- Bundled plugins import core through `discourse_plugin_sdk.dart` and Native UI
  through `discourse_ui.dart`. Cross-plugin imports require an explicit contract
  and declared dependency. Source-boundary tests enforce both directions.
- `calendar_day.dart` remains shared: `topic_view.dart` groups ordinary posts by
  `post.createdAt`, and Chat reuses the same utility through the SDK. Events
  owns event dates and its calendar UI and does not import this utility.

The extension tests install synthetic providers and exercise absent providers,
preference ownership, reserved and overlapping wire fields, schema snapshots,
scoped editing, authenticated search reads, and unavailable search scopes.

## Static checks

The app, `packages/discourse_voice` and `profiles/full` passed
`flutter pub get --enforce-lockfile` and Flutter analysis. The repository's
format check covered 1,971 Dart files with no changes. `git diff --check` passed.

## Test comparison

The final run completed with **12,752 passed, 7 skipped and 49 failed**. All 49
failing cases also failed on the unchanged baseline, whose selected suites
completed with 596 passed and 49 failed. There were no additional failing
cases. The complete repository test gate is therefore not green; these
baseline failures and the diagnostics hang remain outstanding.

The final broad run uses seed `20260922` and every root test file except
`diagnostics_panel_test.dart`. That file failed and then hung during teardown
in both the changed checkout and the isolated baseline during earlier runs;
the final comparison omits it so both runners can finish.

The baseline comparison runs the failing files in a separate detached checkout
of `c42011820`. It also includes `chat_cooking_pipeline_test.dart`, whose worker
settling timeout appeared in an earlier broad run and reproduced on the
baseline. Both cases in that file pass in the final baseline run.

To reproduce the broad run:

```sh
python3 - <<'PY'
from pathlib import Path
import subprocess

files = sorted(
    str(path) for path in Path('test').rglob('*_test.dart')
    if path.name != 'diagnostics_panel_test.dart'
)
raise SystemExit(subprocess.call([
    'flutter', 'test', *files, '--concurrency=8',
    '--test-randomize-ordering-seed=20260922', '--reporter', 'expanded',
]))
PY
```

Baseline failures by file (49 cases):

| Test file | Failing cases |
| --- | ---: |
| `category_notifications_test.dart` | 1 |
| `chat_shell_integration_test.dart` | 2 |
| `composer_drafts_integration_test.dart` | 1 |
| `connection_session_integration_test.dart` | 8 |
| `d_context_menu_test.dart` | 1 |
| `draft_list_test.dart` | 2 |
| `forum_settings_dialog_test.dart` | 2 |
| `forum_tabs_integration_test.dart` | 2 |
| `keyboard_navigation_test.dart` | 2 |
| `post_likes_account_generation_test.dart` | 4 |
| `sidebar_reorder_test.dart` | 4 |
| `site_theme_app_test.dart` | 9 |
| `topic_actions_integration_test.dart` | 1 |
| `topic_reading_integration_test.dart` | 8 |
| `user_summary_test.dart` | 1 |
| `wire_payload_totality_test.dart` | 1 |
