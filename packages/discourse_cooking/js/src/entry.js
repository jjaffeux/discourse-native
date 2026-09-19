import DiscourseMarkdownIt from '../vendor/frontend/discourse-markdown-it/src/index.js';
import { resetTranslationTree } from '../vendor/frontend/discourse-markdown-it/src/features/emoji.js';
import * as spoiler from '../vendor/plugins/spoiler-alert/assets/javascripts/lib/discourse-markdown/spoiler-alert.js';
import * as missingUploads from './missing-uploads.js';
import escape from '../vendor/frontend/discourse/app/lib/escape.js';
import { withSnapshot } from './onebox-cache.js';
import { finalSanitize } from './final-sanitize.js';
import { chatFeatures, chatRules } from './profiles.js';

function own(map, key) { return map && Object.hasOwn(map,key) ? map[key] : undefined; }
function freeze(value, depth = 0) {
  if (depth > 32) throw Error('Snapshot nesting exceeds limit');
  if (value && typeof value === 'object') {
    for (const v of Object.values(value)) freeze(v,depth+1);
    Object.freeze(value);
  }
  return value;
}
const defaults = {
  enable_emoji: true, enable_emoji_shortcuts: true,
  enable_mentions: true, enable_markdown_linkify: true,
  emoji_set: 'twitter', default_code_lang: 'auto', spoiler_enabled: true,
};
const settingsAllowed = [...Object.keys(defaults),'enable_inline_emoji_translation',
  'unicode_usernames','traditional_markdown_linebreaks','enable_markdown_typographer',
  'markdown_typographer_quotation_marks','markdown_linkify_tlds','secure_uploads',
  'external_emoji_url'];

export function cook(serializedRequest) {
  let raw = '';
  try {
    if (typeof serializedRequest !== 'string' || serializedRequest.length > 524288) throw Error('Request exceeds limit');
    const request = JSON.parse(serializedRequest);
    if (typeof request.raw !== 'string') throw Error('raw must be a string');
    raw = request.raw;
    if (raw.length > 65536) throw Error('Input exceeds limit');
    if (!['post','chat'].includes(request.profile)) throw Error('Unknown profile');
    const snapshot = freeze(request.snapshot || {});
    const settings = { ...defaults };
    for (const key of settingsAllowed) {
      const value = own(snapshot.siteSettings,key);
      if (value !== undefined) settings[key] = value;
    }
    const baseUrl = /^https?:\/\/[^/]+(?:\/[^?#]*)?$/.test(snapshot.baseUrl || '') ? snapshot.baseUrl.replace(/\/$/,'') : '';
    const options = {
      siteSettings: settings,
      getURL: path => path.startsWith('/') ? baseUrl + path : path,
      lookupUploadUrls: urls => Object.fromEntries(urls.map(url => [url, own(snapshot.uploads,url)])),
      hashtagLookup: slug => own(snapshot.hashtags,slug),
      getTopicInfo: id => own(snapshot.topics,String(id)),
      lookupAvatar: name => own(snapshot.avatars,name),
      lookupPrimaryUserGroup: () => undefined,
      formatUsername: name => name,
      customEmoji: snapshot.customEmoji,
      customEmojiTranslation: snapshot.customEmojiTranslation,
      allowedIframes: [],
    };
    if (request.profile === 'chat') {
      options.featuresOverride = [...chatFeatures,'offline-missing-uploads'];
      if (settings.enable_emoji_shortcuts) options.featuresOverride.push('emojiShortcuts');
      options.markdownItRules = chatRules;
      options.forceQuoteLink = true;
    }
    resetTranslationTree();
    const html = withSnapshot(snapshot, () => {
      const engine = DiscourseMarkdownIt.withCustomFeatures([
        { id:'spoiler-alert', setup:spoiler.setup, priority:0 },
        { id:'offline-missing-uploads', setup:missingUploads.setup, priority:10 },
      ],[]).withOptions(options);
      return finalSanitize(engine.cook(raw));
    });
    if (html.length > 1048576) throw Error('Output exceeds limit');
    return JSON.stringify({ html, warnings: [] });
  } catch (_error) {
    return JSON.stringify({ html: `<p>${escape(raw.slice(0,65536)).replace(/\n/g,'<br>')}</p>`, warnings:['cooking-failed'], failure:'engine' });
  } finally {
    resetTranslationTree();
  }
}
Object.defineProperty(globalThis, 'cook', { value:cook, writable:false, configurable:false });
