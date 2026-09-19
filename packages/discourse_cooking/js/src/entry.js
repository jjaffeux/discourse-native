import DiscourseMarkdownIt from '../vendor/frontend/discourse-markdown-it/src/index.js';
import { resetTranslationTree } from '../vendor/frontend/discourse-markdown-it/src/features/emoji.js';
import { bundledModules } from 'bundled-modules';

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
    if(typeof request.profile==='string' && !['post','chat'].includes(request.profile)) throw Error('Unknown profile');
    const profile = typeof request.profile === 'string' ? (request.profile==='chat'?{features:chatFeatures,rules:chatRules,forceQuoteLink:true}:{}) : request.profile;
    const declarations = request.configuration?.modules || [{id:'spoiler-alert'},{id:'offline-missing-uploads'}];
    let modules = declarations.map(d=> { const m=bundledModules[d.id]; if(!m || (d.owner && d.owner!==m.owner) || (d.version && d.version!==m.version)) throw Error('Invalid module'); return m; });
    const snapshot = freeze(request.snapshot || {});
    const settings = { ...defaults, ...profile.settings };
    for (const key of settingsAllowed) {
      const value = own(snapshot.siteSettings,key);
      if (value !== undefined) settings[key] = value;
    }
    modules = modules.filter((m,i)=> (!declarations[i].profiles?.length || declarations[i].profiles.includes(profile.name || request.profile)) && (!declarations[i].enabledSetting || (snapshot.pluginContext?.[m.owner]?.settings?.[declarations[i].enabledSetting] ?? settings[declarations[i].enabledSetting]) === true));
    const active=new Set(modules.map(m=>m.id));
    for(const d of declarations) if(active.has(d.id) && (d.dependencies||[]).some(id=>!active.has(id))) active.delete(d.id);
    modules=modules.filter(m=>active.has(m.id));
    const unresolvedReferences=[];
    function lookup(map,key,kind) { const value=own(map,key); if(value===undefined && !unresolvedReferences.some(r=>r.kind===kind && r.key===key)) unresolvedReferences.push({kind,key}); return value; }
    const baseUrl = /^https?:\/\/[^/]+(?:\/[^?#]*)?$/.test(snapshot.baseUrl || '') ? snapshot.baseUrl.replace(/\/$/,'') : '';
    const options = {
      siteSettings: settings,
      getURL: path => path.startsWith('/') ? baseUrl + path : path,
      lookupUploadUrls: urls => Object.fromEntries(urls.map(url => [url, lookup(snapshot.uploads,url,'upload')])),
      hashtagLookup: slug => lookup(snapshot.hashtags,slug,'hashtag'),
      getTopicInfo: id => lookup(snapshot.topics,String(id),'topic'),
      lookupAvatar: name => lookup(snapshot.avatars,name,'mention'),
      lookupPrimaryUserGroup: () => undefined,
      formatUsername: name => name,
      customEmoji: snapshot.customEmoji,
      customEmojiTranslation: snapshot.customEmojiTranslation,
      allowedIframes: [],
    };
    if (profile.features) {
      options.featuresOverride = [...new Set([...profile.features,...modules.filter(m=>m.stage!=='document').map(m=>m.id)])];
      if (settings.enable_emoji_shortcuts) options.featuresOverride.push('emojiShortcuts');
    }
    if(profile.rules) options.markdownItRules = profile.rules;
    options.forceQuoteLink = profile.forceQuoteLink === true;
    resetTranslationTree();
    const html = withSnapshot(snapshot, () => {
      const syntax=modules.filter(m=>m.stage==='syntax').map((m,i)=>({id:m.id,setup:helper=>m.implementation.setup(helper,snapshot.pluginContext?.[m.owner]||{}),priority:i}));
      const transforms=modules.filter(m=>m.stage==='token');
      for(const m of transforms) syntax.push({id:m.id,priority:syntax.length,setup(helper){helper.registerPlugin(md=>md.core.ruler.push(m.id,state=>m.implementation.transform(state.tokens,snapshot.pluginContext?.[m.owner]||{})));}});
      const engine = DiscourseMarkdownIt.withCustomFeatures(syntax,[]).withOptions(options);
      let output=engine.cook(raw);
      for(const m of modules.filter(m=>m.stage==='document')) output=m.implementation.transform(output,snapshot.pluginContext?.[m.owner]||{});
      return finalSanitize(output,modules.map(m=>m.policy));
    });
    if (html.length > 1048576) throw Error('Output exceeds limit');
    return JSON.stringify({ html, warnings: [], unresolvedReferences });
  } catch (_error) {
    return JSON.stringify({ html: `<p>${escape(raw.slice(0,65536)).replace(/\n/g,'<br>')}</p>`, warnings:['cooking-failed'], failure:'engine' });
  } finally {
    resetTranslationTree();
  }
}
Object.defineProperty(globalThis, 'cook', { value:cook, writable:false, configurable:false });
