// Readable fallback until localized immutable snapshots are part of the catalog.
export const i18n = (key) => ({
  'quote': 'Quote', 'expand': 'Expand', 'collapse': 'Collapse',
}[key] || key);
export default { t: i18n };
