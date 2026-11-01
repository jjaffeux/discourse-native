# User Notes

Staff can read, add and remove private notes through post staff actions and positive-count identity icons. The module owns its server schema, settings, records, endpoints, state and Native UI. It uses the shared post/card identity contracts and public account, transport and transient cooking ports.

The upstream reference is Discourse commit `96ce8d44401a8a568ecc71561c26dca8ec6bfeb8`, `plugins/discourse-user-notes`. That version has no edit, search, pagination, notifications or note revision history. Automatic warning notes remain server-owned.

Notes, counts, associations and drafts are memory-only. Each reader borrows an account lease. Account retirement, permission loss, disablement, module close and site forget clear private reader state and abort its cooked-content delivery. The settings codec serializes only non-private configuration. `can_delete` comes from the note serializer, not a locally inferred moderator setting.

The plain textarea retains failed drafts. An uncertain create must be resolved through a refresh before another deliberate submission. No create is automatically retried. The app renders Markdown through transient host cooking and private shared presentation. Private code blocks use uncached syntax highlighting and have no detached fullscreen route. Optional plugin renderers do not process private note content. If the cooker rejects an input or exceeds its budget, the complete raw text remains selectable with an unformatted label and a website link. It never substitutes the cooker's truncated fallback.

The inspected app has no arbitrary-member profile, admin-user or review-item host. Those entry points, review-note copying and admin report UI remain explicit host-dependent deferrals. Related review links use the website. This module does not duplicate those host controllers.
