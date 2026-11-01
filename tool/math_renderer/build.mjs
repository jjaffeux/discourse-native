import { cp, mkdir, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import { dirname, resolve, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
const root = dirname(fileURLToPath(import.meta.url));
const output = resolve(root, '../../lib/src/ui/assets/math');
await mkdir(output, {recursive: true});
for (const [name, paths] of Object.entries({
  mathjax: ['tex-mml-chtml.js', 'tex-mml-svg.js', 'input', 'output', 'a11y', 'ui', 'sre', 'LICENSE'],
  '@mathjax/mathjax-newcm-font': ['chtml', 'svg', 'chtml.js', 'svg.js'],
  katex: ['dist', 'LICENSE'],
})) {
  const destination = resolve(output, name === '@mathjax/mathjax-newcm-font' ? 'newcm' : name);
  await rm(destination, {recursive: true, force: true});
  for (const path of paths) {
    await mkdir(dirname(resolve(destination, path)), {recursive: true});
    await cp(resolve(root, 'node_modules', name, path), resolve(destination, path), {recursive: true});
  }
}
const mapsDirectory = resolve(output, 'mathjax/sre/mathmaps');
const maps = Object.fromEntries(await Promise.all((await readdir(mapsDirectory)).filter(name => name.endsWith('.json')).map(async name => [name.slice(0,-5), JSON.parse(await readFile(resolve(mapsDirectory,name),'utf8'))])));
await writeFile(resolve(output,'speech-maps.js'), 'window.mathSpeechMaps='+JSON.stringify(maps)+';\n');
await writeFile(resolve(output,'speech-worker-source.js'), 'window.mathSpeechWorkerSource='+JSON.stringify(await readFile(resolve(output,'mathjax/sre/speech-worker.js'),'utf8'))+';\n');
const files = [];
async function visit(dir) {
  for (const item of await readdir(dir, {withFileTypes: true})) {
    const path = resolve(dir, item.name);
    if (item.isDirectory()) await visit(path);
    else if (item.name !== 'manifest.json') files.push(path);
  }
}
await visit(output);
files.sort();
await writeFile(resolve(output, 'manifest.json'), JSON.stringify({
  engines: {mathjax: '4.1.0', katex: '0.16.27'},
  files: Object.fromEntries(await Promise.all(files.map(async path => [relative(output,path), createHash('sha256').update(await readFile(path)).digest('hex')]))),
}, null, 2)+'\n');
const pubspec = resolve(root, '../../pubspec.yaml');
let source = await readFile(pubspec, 'utf8');
source = source.replace(/    # BEGIN math assets[\s\S]*?    # END math assets\n/g, '');
const assetFiles = [...files.map(path => relative(output,path)), 'manifest.json'];
source = source.replace('  assets:\n', '  assets:\n    # BEGIN math assets\n'+assetFiles.map(file => `    - packages/discourse_native/src/ui/assets/math/${file}\n`).join('')+'    # END math assets\n');
await writeFile(pubspec, source);
console.log(`Bundled ${files.length} offline math files`);
