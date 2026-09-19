import {parseFragment,serialize,walk,attr} from '../html-document.js';
// URI authority parsing keeps userinfo and ports out of domain comparisons.
function hostname(value) {
  const authority=/^(?:https?:)?\/\/([^/?#]*)/i.exec(value)?.[1];
  if(authority===undefined) return undefined;
  const host=authority.split('@').at(-1).replace(/:\d+$/,'').toLowerCase();
  return /^(?:\[[0-9a-f:]+\]|[^:\s]+)$/i.test(host) ? host : undefined;
}
const domainMatches = (host,domain) => host===domain || host?.endsWith('.'+domain);
export function transform(html, context, api) {
  const doc=parseFragment(html), settings=api.options.siteSettings;
  const siteHost=hostname(api.baseUrl);
  const allowedDomains=(settings.exclude_rel_nofollow_domains||'').split('|').filter(Boolean);
  walk(doc,node=>{
    if(node.tagName==='a') {
      const href=attr(node,'href') || '', host=hostname(href);
      if(attr(node,'target')==='_blank') attr(node,'rel','noopener');
      const malformed=/^(?:https?:)?\/\//i.test(href) && !host;
      if(malformed || (settings.add_rel_nofollow_to_user_content && host && !domainMatches(host,siteHost) && !allowedDomains.some(d=>domainMatches(host,d)))) attr(node,'rel','noopener nofollow ugc');
    }
  });
  return serialize(doc);
}
