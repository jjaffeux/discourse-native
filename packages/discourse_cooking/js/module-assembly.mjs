import vm from 'node:vm';

// Explicit named imports let the bundler reject absent exports. Callable checks
// also run during VM startup, before any request can select a module.
export function assembleModules(modules) {
  const capability = m => m.stage === 'syntax' ? 'setup' : 'transform';
  return modules.map((m,i) => `import { ${capability(m)} as implementation${i} } from './modules/${m.source}';`).join('\n') + '\n' +
    modules.map((m,i) => `if(typeof implementation${i} !== 'function') throw Error(${JSON.stringify('Invalid module implementation: '+m.id)});`).join('\n') +
    '\nexport const bundledModules = {' + modules.map((m,i) => `${JSON.stringify(m.id)}:{...${JSON.stringify(m)},implementation:{${capability(m)}:implementation${i}}}`).join(',') + '};\n';
}

export function validateBundle(bundle) {
  // This is a build-time check for trusted bundled code, not an execution path
  // for user data. No IO, imports, timers, or native host capabilities supplied.
  const result = vm.runInNewContext(bundle, Object.create(null), { timeout:1000, contextCodeGeneration:{strings:false,wasm:false} });
  if(result !== 'ready') throw Error('Bundle did not initialize');
}
