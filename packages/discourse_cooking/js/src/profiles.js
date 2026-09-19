// Pinned from plugins/chat/app/models/chat/message.rb; later milestones supply
// remaining plugin counterparts, bot options, and Ruby cleanup/slash commands.
export const chatFeatures = `anchor bbcode-block bbcode-inline code category-hashtag censored chat-transcript discourse-local-dates emoji inlineEmoji html-img hashtag-autocomplete mentions unicodeUsernames onebox quotes spoiler-alert table text-post-process upload-protocol watched-words chat-html-inline`.split(' ');
export const chatRules = `autolink list backticks newline code fence image table linkify link strikethrough blockquote emphasis replacements escape entity`.split(' ');
