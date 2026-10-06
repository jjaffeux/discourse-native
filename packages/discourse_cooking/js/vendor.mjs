// Run explicitly when upgrading: node vendor.mjs /path/to/discourse [revision]
// Application runtime and regular builds never read a Discourse checkout.
import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
const root = dirname(fileURLToPath(import.meta.url));
const checkout = process.argv[2];
const revision = process.argv[3] || JSON.parse(readFileSync(join(root, 'provenance.json'))).revision;
if (!checkout || !/^[a-f0-9]{40}$/.test(revision)) throw Error('Usage: node vendor.mjs CHECKOUT [FULL_SHA]');
const git = (...args) => execFileSync('git', ['-C', checkout, ...args], { maxBuffer: 32 * 1024 * 1024 });
const directories = ['frontend/discourse-markdown-it/src'];
const requiredFiles = [
  ...['allow-lister','guid','sanitizer','text-replace','emoji','emoji/data','emoji/version','mentions','censored-words'].map(n => `frontend/pretty-text/addon/${n}.js`),
  ...['object','escape','case-converter'].map(n => `frontend/discourse/app/lib/${n}.js`),
  'plugins/spoiler-alert/assets/javascripts/lib/discourse-markdown/spoiler-alert.js',
  'plugins/checklist/assets/javascripts/lib/discourse-markdown/checklist.js',
  'frontend/pretty-text-processor/build.mjs',
  'frontend/pretty-text-processor/pretty-text-ruby-interface.js',
  'plugins/chat/app/models/chat/message.rb',
  'plugins/chat/assets/javascripts/lib/discourse-markdown/chat-html-inline.js',
  'plugins/chat/assets/javascripts/lib/discourse-markdown/chat-transcript.js',
  'plugins/discourse-local-dates/assets/javascripts/lib/discourse-markdown/discourse-local-dates.js',
  'plugins/discourse-details/assets/javascripts/lib/discourse-markdown/details.js',
  'plugins/discourse-details/spec/components/pretty_text_spec.rb',
  'plugins/poll/assets/javascripts/lib/discourse-markdown/poll.js',
  'plugins/poll/spec/lib/pretty_text_spec.rb',
  ...['discourse-post-event-block', 'discourse-calendar', 'livestream-preview'].map(
    name => `plugins/discourse-events/assets/javascripts/discourse/lib/discourse-markdown/${name}.js`
  ),
  'plugins/discourse-events/assets/javascripts/discourse/initializers/livestream-chat-overrides.js',
  'lib/pretty_text.rb',
  'lib/text_cleaner.rb',
  'frontend/discourse-markdown-it/package.json',
  'pnpm-lock.yaml', 'LICENSE.txt'
];
const paths = [...directories, ...requiredFiles, 'COPYRIGHT.txt'];
const files = git('ls-tree','-r','--name-only',revision,'--',...paths)
  .toString().trim().split('\n').filter(Boolean).sort();
const missing = [
  ...requiredFiles.filter(path => !files.includes(path)),
  ...directories.filter(path => !files.some(file => file.startsWith(`${path}/`))),
];
if (missing.length) throw Error(`Missing required upstream sources: ${missing.join(', ')}`);
// Read the complete commit before replacing the current snapshot. An absent
// source or failed Git read must not leave a partially imported bundle.
const sources = files.map(path => [path, git('show', `${revision}:${path}`)]);
rmSync(join(root,'vendor'),{recursive:true,force:true});
const hashes = {};
for (const [path, bytes] of sources) {
  const out = join(root,'vendor',path);
  mkdirSync(dirname(out),{recursive:true}); writeFileSync(out,bytes);
  hashes[path] = createHash('sha256').update(bytes).digest('hex');
}
writeFileSync(join(root,'provenance.json'),JSON.stringify({ repository:'https://github.com/discourse/discourse',revision,sha256:hashes },null,2)+'\n');
