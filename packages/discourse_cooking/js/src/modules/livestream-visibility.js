import {parseFragment,serialize,walk,attr} from '../html-document.js';

// The worker has no event_watching_invitee_status. Preview content remains
// readable; attendance-only content is omitted, including cached html_raw.
export function transform(html) {
  const document = parseFragment(html);
  // Cached html_raw can forge Chat/code wrappers. Exempt only literal marker
  // text there; actual hidden nodes must be removed throughout the document.
  walk(document, node => {
    if (!['div','span'].includes(node.tagName) ||
        !(attr(node, 'class') || '').split(/\s+/).includes('hidden')) return;
    const parent = node.parentNode;
    if (parent) parent.childNodes = parent.childNodes.filter(child => child !== node);
  });
  let hiddenDepth = 0;
  function visit(parent) {
    parent.childNodes = (parent.childNodes || []).filter(node => {
      if (['div','span'].includes(node.tagName) &&
          (attr(node, 'class') || '').split(/\s+/).includes('hidden')) return false;
      if (node.nodeName === '#text') {
        // Unmatched BBCode is otherwise left readable by the upstream parser.
        // Redact it conservatively through the matching close or document end.
        const markers = /\[(\/?)hidden(?:[ \t][^\]\r\n]*)?\]/gi;
        let value = '', offset = 0;
        for (const match of node.value.matchAll(markers)) {
          if (!hiddenDepth) value += node.value.slice(offset, match.index);
          hiddenDepth = match[1] ? Math.max(0, hiddenDepth - 1) : hiddenDepth + 1;
          offset = match.index + match[0].length;
        }
        if (!hiddenDepth) value += node.value.slice(offset);
        node.value = value;
        return value.length > 0;
      }
      // Literal examples do not become visibility directives. A code block
      // inside an already hidden region is still confidential and is removed.
      if (['pre','code'].includes(node.tagName) ||
          (attr(node, 'class') || '').split(/\s+/).includes('chat-transcript')) {
        return !hiddenDepth;
      }
      const startedHidden = hiddenDepth > 0;
      visit(node);
      if (node.content) visit(node.content);
      return !startedHidden || (node.childNodes || []).length > 0;
    });
  }
  visit(document);
  return serialize(document);
}
