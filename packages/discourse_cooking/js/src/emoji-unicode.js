// Pure pinned adapter from pretty-text-ruby-interface.js; see provenance.
import {emojiReplacementRegex} from '../vendor/frontend/pretty-text/addon/emoji.js';
export function buildEmojiUnicodeReplacer(replacements) {
  const regexp = new RegExp(emojiReplacementRegex, "g");
  return function (text) {
    regexp.lastIndex = 0;
    let m;
    while ((m = regexp.exec(text)) !== null) {
      let match = m[0];
      let replacement = replacements[match];
      if (!replacement) {
        match = match.replace(/️$/g, "");
        replacement = replacements[match];
      }
      if (!replacement) {
        continue;
      }
      replacement = ":" + replacement + ":";
      const before = text.charAt(m.index - 1);
      if (!/\B/.test(before)) {
        replacement = "​" + replacement;
      }
      text = text.replace(match, replacement);
    }
    text = text.replace(/️/g, "");
    return text;
  };
}

