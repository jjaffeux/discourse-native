import { readFileSync, realpathSync } from 'node:fs';
import { dirname, isAbsolute, relative, resolve, sep } from 'node:path';
import { createHash } from 'node:crypto';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const sourceName = /^[a-z-]+\.js$/;
const safeManifest = /^lib\/src\/plugins\/[a-z][a-z0-9_]*\/tool\/cooking\/module\.json$/;

function contained(root, path) {
  const file = realpathSync(path);
  const offset = relative(realpathSync(root), file);
  if (offset === '..' || offset.startsWith(`..${sep}`) || isAbsolute(offset)) {
    throw Error('Plugin cooking source escapes its owner directory');
  }
  return file;
}

function verified(path, expected) {
  if (!/^[a-f0-9]{64}$/.test(expected || '') || hash(readFileSync(path)) !== expected) {
    throw Error(`Plugin cooking hash mismatch: ${path}`);
  }
}

export function loadModuleCatalog(entries, repositoryRoot, jsRoot) {
  return entries.map(entry => {
    if (!entry.manifest) {
      if (!sourceName.test(entry.source || '')) throw Error('Invalid module source');
      return entry;
    }
    if (!safeManifest.test(entry.manifest)) throw Error('Invalid plugin cooking manifest path');
    const declaredRoot = resolve(realpathSync(repositoryRoot), dirname(entry.manifest));
    if (realpathSync(declaredRoot) !== declaredRoot) throw Error('Plugin cooking manifest escapes its declared owner directory');
    const manifestPath = contained(declaredRoot, resolve(repositoryRoot, entry.manifest));
    verified(manifestPath, entry.sha256);
    const module = JSON.parse(readFileSync(manifestPath, 'utf8'));
    if (!entry.owner || module.owner !== entry.owner || !sourceName.test(module.source || '')) {
      throw Error('Foreign owner or invalid plugin cooking source');
    }
    if (!module.inputs || typeof module.inputs !== 'object' || !Object.hasOwn(module.inputs, module.source)) {
      throw Error('Plugin cooking manifest must hash every source');
    }
    const actualRoot = realpathSync(declaredRoot);
    for (const [name, digest] of Object.entries(module.inputs)) {
      if (!sourceName.test(name)) throw Error('Invalid plugin cooking input path');
      verified(contained(actualRoot, resolve(actualRoot, name)), digest);
    }
    const source = contained(actualRoot, resolve(actualRoot, module.source));
    return {
      ...module,
      importPath: relative(resolve(jsRoot, 'src'), source).split(sep).join('/'),
      sourceManifest: entry.manifest,
      sourceManifestSha256: entry.sha256,
    };
  });
}

export function pluginSourceImports(modules, repositoryRoot) {
  const owners = modules.filter(module => module.sourceManifest).map(module => {
    const root = realpathSync(resolve(repositoryRoot, dirname(module.sourceManifest)));
    return { root, inputs: new Set(Object.keys(module.inputs).map(name => contained(root, resolve(root, name)))) };
  });
  return (importer, specifier) => {
    if (!isAbsolute(importer)) return undefined;
    const actualImporter = realpathSync(importer);
    const owner = owners.find(owner => actualImporter.startsWith(`${owner.root}${sep}`));
    if (!owner) return undefined;
    if (!specifier.startsWith('./')) throw Error('Plugin cooking imports must stay inside their owner');
    const source = contained(owner.root, resolve(dirname(actualImporter), specifier));
    if (!owner.inputs.has(source)) throw Error('Unhashed plugin cooking import');
    return source;
  };
}
