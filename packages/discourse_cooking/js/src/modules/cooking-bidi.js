import {parseFragment,serialize,walk,attr,textNode} from '../html-document.js';
import {i18n} from '../i18n.js';
export function transform(html, context, api) {
  const doc=parseFragment(html), settings=api.options.siteSettings;
  walk(doc,node=>{
    if(node.tagName==='pre' || node.tagName==='code') {
      walk(node,child=>{
        if(child.nodeName!=='#text' || !/[\u202a-\u202e\u2066-\u2069]/.test(child.value)) return;
        const parts=[];
        for(const c of child.value) {
          if(!/[\u202a-\u202e\u2066-\u2069]/.test(c)) {parts.push(textNode(c,child.parentNode));continue;}
          const warning=parseFragment('<span class="bidi-warning"></span>').childNodes[0];
          warning.parentNode=child.parentNode;attr(warning,'title',i18n('post.hidden_bidi_character',{},api.context.locale));
          warning.childNodes=[textNode('<U+'+c.codePointAt(0).toString(16).toUpperCase()+'>',warning)];parts.push(warning);
        }
        const siblings=child.parentNode.childNodes; siblings.splice(siblings.indexOf(child),1,...parts);
      });
    }
  });
  return serialize(doc);
}
