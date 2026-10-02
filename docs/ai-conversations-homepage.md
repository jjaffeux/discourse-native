# AI conversations homepage

The server registers `ai-conversations` at
`/discourse-ai/ai-bot/conversations` in
`plugins/discourse-ai/lib/ai_bot/entry_point.rb`. `HomepageHelper.resolve`
falls back to the first top-menu item when the registered option is unavailable.
Native resolves this through the AI plugin's `HomepagePlugin` capability;
ordinary topic homepages continue through `ContentRoute.homepage`.

The client settings `discourse_ai_enabled` and `ai_bot_enabled` gate the feature.
For a connected account, `ai_enabled_chat_bots` supplies group-enabled LLM bot
users. Entries with `is_agent: true` are insufficient: the server includes agents
that cannot receive PMs there. `ai_enabled_agents` supplies allowed agents and
`allow_personal_messages` with `username` identifies a PM agent. This also covers
agents allowed outside `ai_bot_allowed_groups`. Startup waits for the fresh
current-user snapshot before committing this registered homepage.

The server can serve an anonymous HTML preview when
`EntryPoint.anonymous_preview_allowed?` permits it, but its JSON list requires
login. Native uses the first anonymous-visible top-menu destination while signed
out. An unavailable feature or missing account capability also uses the regular
top-menu homepage. An API access failure on a previously available route displays
an unavailable state with a Browse forum action.

The authenticated GET endpoint is
`/discourse-ai/ai-bot/conversations.json?page=0`. The current
`ConversationListSerializer` returns `conversations` and
`meta: { page, per_page, has_more }`. Page numbering starts at zero, with 40
unstarred rows by default. The first page prepends starred rows and each row's
`ai_conversation_starred` flag identifies them. Native preserves that server order
and requests the next page only when `meta.has_more` is true. Account leases
prevent a retired account's response from publishing its private list.

Conversation rows open the existing Native PM topic reader. The plugin marks its
list as a private-message source so core preserves it as the return destination.
Homepage selection, `/` links and a cold return from a plugin pane use the same
resolver. Existing Voice history returns to that preserved destination; joining
or leaving the call keeps its current behavior.

This flow lists and opens existing conversations. Creating new AI conversations,
star management, agent selection and anonymous AI preview UI are outside this
homepage change.

Contract inspected in the local Discourse checkout at
`67bc74d0d83f8037ec538c1299b8d8cb59211319`, including commit
`1057dafc7f7eaba58b5d37198e024b1f151ad156`, the homepage specs, conversation
controller and serializer, `ConversationStar.list`, and the Voice room route and
`dockRoom` implementation.
