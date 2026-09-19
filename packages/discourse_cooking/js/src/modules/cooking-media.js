import {parseFragment,serialize,walk,attr} from '../html-document.js';
export function transform(html, context, api) {
  const doc=parseFragment(html), settings=api.options.siteSettings;
  const allowedMedia=[api.baseUrl,...api.allowedMediaOrigins,settings.external_emoji_url,...(settings.block_hotlinked_media_exceptions||'').split('|')].filter(Boolean);
  walk(doc,node=>{
    if(settings.block_hotlinked_media && ['img','source','track','div'].includes(node.tagName)) {
      for(const key of ['src','data-video-src','data-orig-src']) {
        const url=attr(node,key);if(!url) continue;
        const allowed=/^\/(?!\/)/.test(url) || allowedMedia.some(prefix=>url===prefix || url.startsWith(prefix.replace(/\/$/,'')+'/'));
        if(!allowed) {attr(node,'data-blocked-hotlinked-src',url);attr(node,key,null);}
      }
    }
    if(node.tagName==='div' && (attr(node,'class')||'').split(' ').includes('video-placeholder-container')) {
      const metadata=api.lookup('media',attr(node,'data-video-src'));
      if(metadata) {
        if(metadata.thumbnailUrl) attr(node,'data-thumbnail-src',metadata.thumbnailUrl);
        if(metadata.videoBase62Sha1) attr(node,'data-video-base62-sha1',metadata.videoBase62Sha1);
      }
    }
  });
  return serialize(doc);
}
