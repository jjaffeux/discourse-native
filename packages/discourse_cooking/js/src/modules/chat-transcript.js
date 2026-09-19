import { createSetup } from '../../vendor/plugins/chat/assets/javascripts/lib/discourse-markdown/chat-transcript.js';
import escape from '../../vendor/frontend/discourse/app/lib/escape.js';
import {i18n} from '../i18n.js';
import { chatFeatures, chatRules } from '../profiles.js';

export function setup(helper, context, api) {
  const setup = createSetup((key,values)=>i18n(key,values,api.context.locale));
  helper.allowList(['div[data-chained]', 'div[data-reactions]', 'div[data-multiquote]',
    'div[data-thread-id]', 'div[data-thread-title]']);
  // Register restricted HTML even for post parents; nested Chat needs it.
  helper.registerOptions(options => {
    options.additionalOptions = { ...options.additionalOptions, chat: {
      limited_pretty_text_features: [...chatFeatures, ...api.activeFeatures,
        ...(api.options.siteSettings.enable_emoji_shortcuts ? ['emojiShortcuts'] : [])],
      limited_pretty_text_markdown_rules: chatRules,
      hashtag_configurations: {'chat-composer': api.hashtagPriorities.chat || ['channel','category','tag']},
    }};
  });
  setup({
    allowList: values => helper.allowList(values),
    registerOptions: callback => helper.registerOptions(options => callback(options, {chat_enabled:true})),
    registerPlugin: callback => helper.registerPlugin(md => {
      const ruler=md.block.bbcode.ruler, push=ruler.push;
      ruler.push=function(name,rule) {
        push.call(this,name,{...rule,replace(state,tag,content){
          const attrs={...tag.attrs};
          for(const key of ['channel','threadTitle']) if(attrs[key]) attrs[key]=escape(attrs[key]);
          for(const key of ['channelId','threadId']) if(attrs[key] && !/^[1-9][0-9]*$/.test(attrs[key])) delete attrs[key];
          if(attrs.reactions && !attrs.reactions.split(';').every(r=>/^[^:;]+:[^:;]+$/.test(r))) delete attrs.reactions;
          return rule.replace(state,{...tag,attrs},content);
        }});
      };
      try {callback(md);} finally {ruler.push=push;}
    }),
    buildCookFunction: callback => helper.buildCookFunction((options, generate) => {
      // Upstream's nested builder discards non-rule overrides. Bind these to
      // the nested parser directly, preserving the parent's post context.
      callback(options, (nested, ready) => generate({...nested,forceQuoteLink:true}, cook => ready(cook)));
    }),
  });
}
