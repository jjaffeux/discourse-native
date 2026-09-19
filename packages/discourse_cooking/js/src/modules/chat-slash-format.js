import {parseFragment,serialize,textNode,attr} from '../html-document.js';
export function transform(html, context, api) {
 const command=api.state.command;if(!command) return html;
 const doc=parseFragment(html), elements=doc.childNodes.filter(n=>n.tagName);
 if(elements.length>1 || (elements.length===1 && elements[0].tagName!=='p')) return html;
 let p=elements[0];
 if(command.name==='me') {
  if(!p) return html;
  const em=parseFragment('<em></em>').childNodes[0];attr(em,'class','chat-message-action');
  em.parentNode=p;em.childNodes=[textNode(command.author+' ',em),...p.childNodes];
  for(const n of em.childNodes) n.parentNode=em;
  p.childNodes=[em];
 } else {
  if(!p) {p=parseFragment('<p></p>').childNodes[0];p.parentNode=doc;doc.childNodes.push(p);}
  p.childNodes.push(textNode((p.childNodes.length?' ':'')+command.text,p));
 }
 return serialize(doc);
}
