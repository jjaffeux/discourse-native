export function transform(html, context) {
 return html + (context.append || '');
}
