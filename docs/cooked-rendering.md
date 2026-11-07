# Cooked rendering context

`CookedHtml` remains the application entry point and renders through
`HtmlWidget`. Native controls and plugin claims replace recognized elements;
unrecognized markup continues through the HTML renderer.

```dart
CookedHtml(
  html: displayedCooked,
  siteUrl: siteUrl,
  post: post,
  containingTopic: topic,
);
```

## Document and fragment ownership

The mounted boundary resolves a `CookedDocument` from displayed and saved HTML.
The document owns checklist compatibility, annotation and whole-post target
indexes. Its bounded, value-keyed checklist cache survives remounts and fresh
post records with unchanged content.

`CookedDocument.bind` issues a `CookedContent` port. Details, spoilers, table
cells and task prose receive that port:

```dart
Widget? cookedDetailsWidgetBuilder(
  dom.Element element, {
  required CookedContent content,
});

// The adapter supplies its selected markup and any local style override.
content(context, bodyHtml);
```

The port creates a document-owned `CookedFragment` and returns to the same
`CookedHtml` boundary. Fragments retain the root's context and checkbox indexes.
They do not derive a new whole-post checklist or copy its dependency snapshot.
Disclosure and table state keys retain their normalized subtree content keys,
so checkbox changes preserve local state and edits to that subtree reset it.

## Body reuse and actions

`CookedRenderContext` carries the resolved document, source site, registry,
post/topic context and narrow link/checklist actions. `CookedRenderInputs` is an
immutable value snapshot used as the HTML rebuild trigger. Its body values
compare plugin-owned body records, link counts, mentioned statuses, checklist
targets, post ID/number and permissions. Its presentation values include text
metrics, locale, direction, search colors and layout options.

The snapshot excludes whole `Post` instances, action callbacks and records
owned only by footer plugins. Reactions and likes reuse the body. Changes to a
body plugin's records, source identity or presentation invalidate it. Collection
snapshots compare by content, including status maps with different entry order.

Cached checkbox and link handlers call the mounted action adapter. It reads the
latest resolved post and source site when invoked, so a body-cache hit does not
freeze an earlier post revision. Checklist actions also recheck the current
connection before dispatch.

`HtmlWidget` creates its factory once. `SiteImageWidgetFactory` therefore reads
current site, registry, middle-click action and progressive mode through one
configuration getter. Changes refresh that factory without remounting the
Native disclosure or table state.

## Design choice and compatibility

Two designs were considered: one combined document/input/action owner, and
separate document ownership, immutable render values and mounted actions. The
second makes cache equality independent of callback lifetime. The shared
`CookedContent` port keeps nested adapters from coordinating those lifetimes.

The existing claim order is retained, including nested post-body plugin claims,
Native concealment before descendant construction and HTML fallthrough. Quotes
and oneboxes retain their separate postless compatibility boundaries. Table
copy/sort/paging, code selection/copy, source-range checkboxes, authenticated site
context and accessibility remain with their existing owners.

The implementation still serializes selected nested markup and uses the existing
HTML parser. It makes no parsing or frame-rate claim. A deeper projection or
parser change needs a measured experiment before adoption.

Focused coverage lives in `test/cooked_render_context_test.dart`,
`test/cooked_html_test.dart`, `test/posted_todos_test.dart`, the
`test/cooked_{details,spoiler,table,site_identity,markup_totality}_test.dart`
suites, and the selection, code, site-image and progressive rendering suites.

## Cooking source dependencies

`CookingContextOwner` parses each raw source's bounded topic and user references
once for its request or watch. Snapshot assembly, preflight freshness and watch
notifications share that selection. Entity freshness compares only the cached
fields projected into cooking metadata: topic titles and referenced user
usernames/avatar URLs, including missing values that can arrive later.

A change to an unrelated record, or to an unused field on a referenced record,
does not stale a prepared request. Previously requests compared whole-site entity
generations while watchers observed selected refs, so unrelated arrivals could
silently discard cooked work without scheduling a replacement. Relevant metadata
arrival or change now invalidates the request and notifies its watch consistently.

Source snapshots retain small immutable scalar tuples, not entity objects or
new per-request listeners. Request tracking remains weakly keyed by the original
`CookingRequest`. Existing 65,536-character and 128-reference bounds remain in
force. Account generations, application context revisions, settings, identity,
presentation and timezone checks retain their existing authority.

Using broad Store notifications instead would recook all watched sources for
unrelated records. Registered structural dependencies would need an explicit
request disposal lifetime. The bounded source snapshot avoids both changes.
Freshness, headless context and Chat cooking tests pin the shared selection,
relevant arrivals, immutable worker requests and consumer lifetime.
