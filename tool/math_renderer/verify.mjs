import {readFile,readdir} from 'node:fs/promises';
import {resolve,dirname,relative} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'../../lib/src/ui/assets/math');
const manifest=JSON.parse(await readFile(resolve(root,'manifest.json'),'utf8'));
const files=[];
async function visit(directory) {for(const entry of await readdir(directory,{withFileTypes:true})) {const path=resolve(directory,entry.name);if(entry.isDirectory())await visit(path);else if(entry.name!=='manifest.json')files.push(relative(root,path));}}
await visit(root);
if(JSON.stringify(files.sort())!==JSON.stringify(Object.keys(manifest.files).sort()))throw Error('Asset file set differs from manifest');
for(const [path,expected] of Object.entries(manifest.files)) {
  const actual=createHash('sha256').update(await readFile(resolve(root,path))).digest('hex');
  if(actual!==expected)throw Error(`Asset hash differs: ${path}`);
}
console.log(`Verified ${files.length} offline math assets`);
