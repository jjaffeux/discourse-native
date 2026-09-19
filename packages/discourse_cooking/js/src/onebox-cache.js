let snapshot;
export function withSnapshot(value, callback) {
  if (snapshot) throw new Error('Reentrant cook');
  snapshot = value;
  try { return callback(); } finally { snapshot = undefined; }
}
function own(map, key) {
  return map && Object.prototype.hasOwnProperty.call(map, key) ? map[key] : undefined;
}
export function lookupCache(url) { return own(snapshot?.oneboxes, url); }
export function cachedInlineOnebox(url) { return own(snapshot?.inlineOneboxes, url); }
