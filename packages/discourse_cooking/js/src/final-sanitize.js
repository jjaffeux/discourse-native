import xss from 'xss';
// A closed final policy also applies to upstream html_raw hoists (cached oneboxes,
// quotes, plugins). Neither site settings nor plugin callbacks may weaken it.
// No iframe, SVG, MathML, style, event handlers, or arbitrary URL schemes.
const attributes = {
  a: ['href','title','class','target','rel','name','data-orig-href','data-type','data-slug','data-ref','data-id','data-style-type','data-icon','data-emoji'],
  img: ['src','alt','title','class','width','height','loading','role','data-orig-src','data-base62-sha1'],
  aside: ['class','data-topic','data-post','data-username'],
  div: ['class','dir','lang'], span: ['class','lang'],
  ol: ['start','reversed','type'], li: ['class'],
  code: ['class'], pre: ['class'],
  th: ['colspan','rowspan','align'], td: ['colspan','rowspan','align'],
  audio: ['controls','preload'], video: ['controls','preload','width','height'],
  source: ['src','type'], track: ['src','kind','label','srclang'],
};
for (const tag of 'p br hr strong em b i s del ins strike u blockquote ul dl dt dd h1 h2 h3 h4 h5 h6 table thead tbody tr tfoot caption kbd mark sub sup small ruby rb rp rt'.split(' ')) attributes[tag] ||= [];
export function finalSanitize(html, additions = []) {
  const policy=Object.fromEntries(Object.entries(attributes).map(([tag,attrs])=>[tag,[...attrs]]));
  for(const addition of additions) for(const [tag,attrs] of Object.entries(addition)) {
    if(!/^(?:img|em|mark|span|div|details|summary|time|kbd|abbr|a|pre|code|aside|li|p|ol|ul|blockquote|table|td|th)$/.test(tag)) throw Error('Unsafe policy tag');
    for(const attr of attrs) { if(!(attr==='open' && tag==='details') && !/^(?:class|title|datetime|data-[a-z0-9-]+|aria-[a-z0-9-]+)$/.test(attr) || (/^data-.*(?:url|href|src)/.test(attr) && !['data-url','data-orig-href','data-orig-src','data-video-src','data-thumbnail-src','data-blocked-hotlinked-src'].includes(attr))) throw Error('Unsafe policy attribute'); }
    policy[tag]=[...new Set([...(policy[tag]||[]),...attrs])];
  }
  return xss(html, {
    whiteList: policy,
    stripIgnoreTag: true,
    // Opaque/raw-text containers must not become active markup when unwrapped.
    stripIgnoreTagBody: ['script','style','iframe','object','embed','svg','math',
      'xmp','plaintext','noembed','noframes','noscript','textarea','title'],
    onTagAttr(tag, name, value, isWhiteAttr) {
      if (['href','src','data-url','data-image','data-orig-src','data-orig-href','data-video-src','data-thumbnail-src','data-blocked-hotlinked-src'].includes(name)) {
        // xss calls this hook BEFORE normalization. Validate the normalized
        // value, then emit it escaped exactly once instead of letting a second
        // default normalization change the URL after the policy check.
        if (!isWhiteAttr) return '';
        const normalized = xss.friendlyAttrValue(value);
        if (!/^(?:https?:\/\/|\/(?!\/)|#|mailto:)/i.test(normalized)) return '';
        return `${name}="${xss.escapeAttrValue(normalized)}"`;
      }
    },
  });
}
