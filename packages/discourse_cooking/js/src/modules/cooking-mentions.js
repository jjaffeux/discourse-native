import {parseFragment,serialize,walk,attr,text,textNode} from '../html-document.js';
export function transform(html, context, api) {
  const doc=parseFragment(html), settings=api.options.siteSettings;
  walk(doc,node=>{
    if(node.tagName==='span' && attr(node,'class')==='mention' && settings.enable_mentions) {
      const name=text(node).slice(1).toLowerCase();
      const known=api.lookup('mentions',name);
      // Legacy boolean presence cannot prove kind, canonical spelling or eligibility.
      if(known && ['user','group','group-mentionable'].includes(known.kind) && typeof known.href==='string') {
        node.nodeName=node.tagName='a';attr(node,'href',known.href);
        attr(node,'class',known.kind==='user'?'mention':known.kind==='group-mentionable'?'mention-group notify':'mention-group');
        if(typeof known.username==='string') node.childNodes=[textNode('@'+known.username,node)];
      }
    }
  });
  return serialize(doc);
}
