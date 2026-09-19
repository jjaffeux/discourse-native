// Unknown uploads are visible text, not invisible placeholders or broken 404
// links. Runs on parsed tokens, so code and other protected text are untouched.
export function setup(helper) {
  helper.registerPlugin(md => {
    md.core.ruler.after('upload-protocol', 'offline-missing-uploads', state => {
      function visit(tokens) {
        for (const token of tokens) {
          if (token.type === 'image' && token.attrGet('data-orig-src')) {
            const label = token.children?.map(t => t.content).join('') || 'upload';
            token.type = 'text'; token.tag = ''; token.attrs = null;
            token.content = `[${label}]`; token.children = null;
          } else if (token.type === 'link_open' && token.attrGet('data-orig-href')) {
            token.attrs = token.attrs.filter(([name]) => name !== 'href');
          }
          if (token.children) visit(token.children);
        }
      }
      visit(state.tokens);
    });
  });
}
