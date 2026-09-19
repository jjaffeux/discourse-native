export function transform(tokens, context) {
 for(const token of tokens) {
  if(token.children) transform(token.children,context);
  if(token.type==='text' && context.replace) token.content=token.content.replaceAll('TOKEN',context.replace);
 }
}
