import test from 'node:test';
import assert from 'node:assert/strict';
import { build } from 'esbuild';
import { assembleModules, validateBundle } from '../module-assembly.mjs';

async function fixture(source,stage='syntax') {
 const module={id:'fixture',owner:'fixture',version:'1',source:'fixture.js',stage,policy:{}};
 const result=await build({stdin:{contents:assembleModules([module]),resolveDir:'/'},bundle:true,write:false,format:'iife',platform:'neutral',logLevel:'silent',plugins:[{name:'memory-fixture',setup(b){b.onResolve({filter:/fixture\.js$/},()=>({path:'fixture',namespace:'fixture'}));b.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:source}));}}]});
 return result.outputFiles[0].text+'\n"ready";';
}
test('assembly rejects comment-only missing export during build',async()=>{
 await assert.rejects(fixture('// export function setup() {}\nexport const other = true;'),/No matching export/);
});
test('assembly rejects non-callable stages during initialization',async()=>{
 for(const stage of ['syntax','token','document']) {
  const name=stage==='syntax'?'setup':'transform';
  assert.throws(()=>validateBundle('"not-ready"'),/did not initialize/);
  const bundle=await fixture(`export const ${name} = 42;`,stage);
  assert.throws(()=>validateBundle(bundle),/Invalid module implementation/);
 }
});
test('assembly accepts callable stages without any host IO',async()=>{
 for(const stage of ['syntax','token','document']) {
  const name=stage==='syntax'?'setup':'transform';
  validateBundle(await fixture(`export function ${name}() {}`,stage));
 }
});
