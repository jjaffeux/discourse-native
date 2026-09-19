// Run explicitly when upgrading: node vendor.mjs /path/to/discourse [revision]
// Application runtime and regular builds never read a Discourse checkout.
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
const root = dirname(fileURLToPath(import.meta.url));
const checkout = process.argv[2];
const revision = process.argv[3] || '07a0e7b94717b45207749578df1f0bd2dd4d12e1';
if (!checkout || !/^[a-f0-9]{40}$/.test(revision)) throw Error('Usage: node vendor.mjs CHECKOUT [FULL_SHA]');
const git = (...args) => execFileSync('git', ['-C', checkout, ...args], { maxBuffer: 32 * 1024 * 1024 });
const paths = [
  'frontend/discourse-markdown-it/src',
  ...['allow-lister','guid','sanitizer','text-replace','emoji','emoji/data','emoji/version','mentions','censored-words'].map(n => `frontend/pretty-text/addon/${n}.js`),
  ...['object','escape','case-converter'].map(n => `frontend/discourse/app/lib/${n}.js`),
  'plugins/spoiler-alert/assets/javascripts/lib/discourse-markdown/spoiler-alert.js',
  'frontend/pretty-text-processor/build.mjs',
  'frontend/pretty-text-processor/pretty-text-ruby-interface.js',
  'plugins/chat/app/models/chat/message.rb',
  'frontend/discourse-markdown-it/package.json',
  'pnpm-lock.yaml', 'LICENSE.txt', 'COPYRIGHT.txt'
];
const files = git('ls-tree','-r','--name-only',revision,'--',...paths).toString().trim().split('\n').sort();
rmSync(join(root,'vendor'),{recursive:true,force:true});
const hashes = {};
for (const path of files) {
  const bytes = git('show',`${revision}:${path}`);
  const out = join(root,'vendor',path);
  mkdirSync(dirname(out),{recursive:true}); writeFileSync(out,bytes);
  hashes[path] = createHash('sha256').update(bytes).digest('hex');
}
writeFileSync(join(root,'provenance.json'),JSON.stringify({ repository:'https://github.com/discourse/discourse',revision,sha256:hashes },null,2)+'\n');
