import {buildEmojiUnicodeReplacer} from './emoji-unicode.js';
import {setLocale} from './i18n.js';
import {replacements as unicodeReplacements} from '../vendor/frontend/pretty-text/addon/emoji/data.js';
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
  'external_emoji_url','add_rel_nofollow_to_user_content','exclude_rel_nofollow_domains','block_hotlinked_media','block_hotlinked_media_exceptions'];

export function cook(serializedRequest) {
  let raw = '';
  const cleanups=[];
  try {
    if (typeof serializedRequest !== 'string' || serializedRequest.length > 524288) throw Error('Request exceeds limit');
    const request = JSON.parse(serializedRequest);
    if (typeof request.raw !== 'string') throw Error('raw must be a string');
    raw = request.raw;
    if (raw.length > 65536) throw Error('Input exceeds limit');
    if(typeof request.profile==='string' && !['post','chat'].includes(request.profile)) throw Error('Unknown profile');
    const profile = typeof request.profile === 'string' ? (request.profile==='chat'?{features:chatFeatures,rules:chatRules,forceQuoteLink:true}:{}) : request.profile;
    const declarations = request.configuration?.modules || [{id:'spoiler-alert'},{id:'offline-missing-uploads'}];
    const availableModules = declarations.map(d=> { const m=bundledModules[d.id]; if(!m || (d.owner && d.owner!==m.owner) || (d.version && d.version!==m.version)) throw Error('Invalid module'); return m; });
    const snapshot = freeze(request.snapshot || {});
    setLocale(snapshot.context?.locale);
    function settingsFor(selectedProfile) {
      const selected = {...defaults, ...selectedProfile.settings};
      for (const key of settingsAllowed) {
        const value = own(snapshot.siteSettings,key);
        if (value !== undefined) selected[key] = value;
      }
      return selected;
    }
    function resolveProfile(name) {
      return request.configuration?.profiles?.find(p=>p.name===name) ||
        (name==='chat'?{features:chatFeatures,rules:chatRules,forceQuoteLink:true}:name==='post'?{}:null);
    }
    const settings = settingsFor(profile);
    function selectModules(name, selectedSettings = settingsFor(resolveProfile(name) || {})) {
      const selected = availableModules.filter((m,i)=> (!declarations[i].profiles?.length || declarations[i].profiles.includes(name)) && (!declarations[i].enabledSetting || (snapshot.pluginContext?.[m.owner]?.settings?.[declarations[i].enabledSetting] ?? selectedSettings[declarations[i].enabledSetting]) === true));
      const active = new Set(selected.map(m=>m.id));
      // Dependencies can themselves become inactive after profile filtering.
      let changed;
      do {
        changed = false;
        for (const d of declarations) if (active.has(d.id) && (d.dependencies || []).some(id=>!active.has(id))) {
          active.delete(d.id); changed = true;
        }
      } while (changed);
      return selected.filter(m=>active.has(m.id));
    }
    const modules = selectModules(profile.name || request.profile, settings);
    const active = new Set(modules.map(m=>m.id));
    const usedPolicies = new Set(modules.map(m=>m.policy));
    const unresolvedReferences=[];
    function lookup(map,key,kind) { if(typeof key!=='string' || !key) return undefined; const value=own(map,key); if(kind && value===undefined && !unresolvedReferences.some(r=>r.kind===kind && r.key===key)) unresolvedReferences.push({kind,key}); return value; }
    const baseUrl = /^https?:\/\/[^/]+(?:\/[^?#]*)?$/.test(snapshot.baseUrl || '') ? snapshot.baseUrl.replace(/\/$/,'') : '';
    const options = {
      siteSettings: settings,
      getURL: path => path.startsWith('/') ? baseUrl + path : path,
      lookupUploadUrls: urls => Object.fromEntries(urls.map(url => [url, lookup(snapshot.uploads,url,'upload')])),
      hashtagLookup: (slug,userId,types=[]) => {
        for(const type of types) {const value=own(snapshot.hashtags,slug+'::'+type);if(value) return value;}
        return lookup(snapshot.hashtags,slug,'hashtag');
      },
      hashtagTypesInPriorityOrder: snapshot.hashtagPriorities?.post || ['category','tag'],
      hashtagIcons: snapshot.hashtagIcons || {},
      emojiDenyList: snapshot.emojiDenyList || [],
      censoredRegexp: snapshot.censoredRegexp || [],
      watchedWordsReplace: snapshot.watchedWordsReplace || {},
      watchedWordsLink: snapshot.watchedWordsLink || {},
      getTopicInfo: id => {const topic=lookup(snapshot.topics,String(id),'topic');return topic?{...topic,title:escape(topic.title||'')}:undefined;},
      lookupAvatar: name => lookup(snapshot.avatars,name,'mention'),
      lookupPrimaryUserGroup: name => own(snapshot.primaryGroups,name),
      formatUsername: name => escape(name),
      userId: snapshot.context?.editorId ?? snapshot.context?.authorId,
      topicId: snapshot.context?.topicId, postId: snapshot.context?.postId,
      customEmoji: snapshot.customEmoji,
      emojiUnicodeReplacer: buildEmojiUnicodeReplacer({...unicodeReplacements,...snapshot.unicodeEmoji}),
      customEmojiTranslation: snapshot.customEmojiTranslation,
      allowedIframes: [],
    };
    if (profile.features) {
      options.featuresOverride = [...new Set([...profile.features,...modules.filter(m=>m.stage!=='document').map(m=>m.id)])];
      if (settings.enable_emoji_shortcuts) options.featuresOverride.push('emojiShortcuts');
    }
    if(profile.rules) options.markdownItRules = profile.rules;
    options.forceQuoteLink = profile.forceQuoteLink === true;
    const rootScope = {options, modules, profile:profile.name || request.profile, states:new Map()};
    const nestedEngines = new Map();
    const apiFor = (m, scope = rootScope) => ({context:snapshot.context || {}, profile:scope.profile,
      options:scope.options, baseUrl, allowedMediaOrigins:snapshot.allowedMediaOrigins || [], activeFeatures:scope.modules.filter(m=>['syntax','token'].includes(m.stage)).map(m=>m.id), hashtagPriorities:snapshot.hashtagPriorities || {}, onCleanup:callback=>cleanups.push(callback), state:scope.states.get(m.owner) || (scope.states.set(m.owner,{}),scope.states.get(m.owner)),
      policiesForProfile:name=>selectModules(name).map(m=>m.policy),
      cookProfile:(name, source, overrides = {})=> {
        const key = JSON.stringify([name, overrides]);
        let nestedEngine = nestedEngines.get(key);
        if (!nestedEngine) {
          const selectedProfile = resolveProfile(name);
          if (!selectedProfile) throw Error('Unknown nested profile');
          const nestedModules = selectModules(name);
          const nestedSettings = settingsFor(selectedProfile);
          const nestedOptions = {...options, siteSettings:nestedSettings,
            featuresOverride:selectedProfile.features ? [...selectedProfile.features, ...nestedModules.filter(m=>['syntax','token'].includes(m.stage)).map(m=>m.id), ...(nestedSettings.enable_emoji_shortcuts?['emojiShortcuts']:[])] : undefined,
            markdownItRules:selectedProfile.rules, forceQuoteLink:selectedProfile.forceQuoteLink===true,
            ...overrides,
          };
          if(nestedOptions.featuresOverride) nestedOptions.featuresOverride=nestedOptions.featuresOverride.filter(id=>!bundledModules[id] || nestedModules.some(m=>m.id===id));
          const nestedScope = {options:nestedOptions, modules:nestedModules, profile:name, states:new Map()};
          nestedEngine = makeEngine(nestedScope);
          nestedEngines.set(key, nestedEngine);
          for (const nested of nestedModules) usedPolicies.add(nested.policy);
        }
        return nestedEngine.cook(source);
      },
      lookup:(namespace,key)=>{
        const kinds={uploads:'upload',mentions:'mention',avatars:'mention',hashtags:'hashtag',topics:'topic',oneboxes:'onebox',media:null,primaryGroups:null};
        if(!Object.hasOwn(kinds,namespace)) throw Error('Unknown lookup namespace');
        return lookup(snapshot[namespace],key,kinds[namespace]);
      }});
    function makeEngine(scope) {
      const syntax=scope.modules.filter(m=>m.stage==='syntax').map((m,i)=>({id:m.id,setup:helper=>m.implementation.setup(helper,snapshot.pluginContext?.[m.owner]||{},apiFor(m,scope)),priority:i}));
      for(const m of scope.modules.filter(m=>m.stage==='token')) syntax.push({id:m.id,priority:syntax.length,setup(helper){helper.registerPlugin(md=>md.core.ruler.push(m.id,state=>m.implementation.transform(state.tokens,snapshot.pluginContext?.[m.owner]||{},apiFor(m,scope))));}});
      return DiscourseMarkdownIt.withCustomFeatures(syntax,[]).withOptions(scope.options);
    }
    let source = raw;
    if(snapshot.context?.sourcePolicy === 'submission') source=source
      .replace(/[\u00a0\u1680\u180e\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]/g,' ')
      .replace(/^[ \t\r\n\v\f\0]+|[ \t\r\n\v\f\0]+$/g,'').replace(/\u200b/g,'');
    for(const m of modules.filter(m=>m.stage==='source')) {
      source=m.implementation.transform(source,snapshot.pluginContext?.[m.owner]||{},apiFor(m));
      if(typeof source!=='string' || source.length>65536) throw Error('Invalid source stage result');
    }
    // A selected profile cannot reactivate an absent optional implementation.
    if(options.featuresOverride) options.featuresOverride=options.featuresOverride.filter(id=>!bundledModules[id] || active.has(id));
    resetTranslationTree();
    const html = withSnapshot(snapshot, () => {
      const engine = makeEngine(rootScope);
      let output=engine.cook(source);
      for(const m of modules.filter(m=>m.stage==='document')) output=m.implementation.transform(output,snapshot.pluginContext?.[m.owner]||{},apiFor(m));
      return finalSanitize(output,[...usedPolicies]);
    });
    if (html.length > 1048576) throw Error('Output exceeds limit');
    return JSON.stringify({ html, warnings: [], unresolvedReferences });
  } catch (_error) {
    return JSON.stringify({ html: `<p>${escape(raw.slice(0,65536)).replace(/\n/g,'<br>')}</p>`, warnings:['cooking-failed'], failure:'engine' });
  } finally {
    resetTranslationTree();
    for(const cleanup of cleanups.reverse()) cleanup();
    setLocale('en');
  }
}
Object.defineProperty(globalThis, 'cook', { value:cook, writable:false, configurable:false });
