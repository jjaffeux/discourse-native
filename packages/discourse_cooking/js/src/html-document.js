import {parseFragment, serialize} from 'parse5';
export {parseFragment, serialize};
export function attr(node,name,value) {
  const entry=node.attrs?.find(a=>a.name===name);
  if(arguments.length===2) return entry?.value;
  if(value===null) node.attrs=node.attrs.filter(a=>a.name!==name);
  else if(entry) entry.value=String(value);
  else (node.attrs ||= []).push({name,value:String(value)});
}
export function walk(node,visit) {visit(node);for(const child of [...(node.childNodes||[])]) walk(child,visit);}
export function text(node) {return node.nodeName==='#text' ? node.value : (node.childNodes||[]).map(text).join('');}
export function textNode(value,parentNode) {return {nodeName:'#text',value,parentNode};}
