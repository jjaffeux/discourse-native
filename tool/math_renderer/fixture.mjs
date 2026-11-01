import {cp,mkdir,readFile,writeFile} from 'node:fs/promises';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=dirname(fileURLToPath(import.meta.url));
const output=resolve(process.argv[2] || '/tmp/native-math-check');
await mkdir(output,{recursive:true});
await cp(resolve(root,'../../lib/src/ui/assets/math'),output,{recursive:true});
const cases=[
  {name:'MathJax HTML fraction',config:{engine:'mathjax',output:'html',accessibility:false},source:'\\frac{a}{b}',selector:'mjx-mfrac'},
  {name:'MathJax SVG fraction',config:{engine:'mathjax',output:'svg',accessibility:false},source:'\\frac{a}{b}',selector:'svg'},
  {name:'MathJax ASCII',config:{engine:'mathjax',output:'html',accessibility:false},input:'ascii',source:'sqrt(x^2+1)',selector:'mjx-msqrt'},
  {name:'MathJax chemistry',config:{engine:'mathjax',output:'html',accessibility:false},source:'\\ce{H2O}',selector:'mjx-container'},
  {name:'MathJax enriched',config:{engine:'mathjax',output:'html',accessibility:true},source:'x^2+1',selector:'[data-semantic-type]'},
  {name:'KaTeX chemistry',config:{engine:'katex'},source:'\\ce{CO2 + C -> 2 CO}',selector:'.katex'},
  {name:'KaTeX unsafe URL',config:{engine:'katex'},source:'\\href{javascript:alert(1)}{x}',selector:'.katex',reject:'a[href^="javascript:"]'},
  {name:'KaTeX reference',config:{engine:'katex'},source:'\\eqref{energy}',selector:'a[href="#energy"]'},
  {name:'MathJax invalid context isolated',config:{engine:'mathjax',output:'html',accessibility:false},source:'x+1',context:[{source:'\\notARealCommand',input:'tex',display:false},{source:'x+1',input:'tex',display:false}],contextIndex:1,selector:'mjx-container'},
  {name:'KaTeX invalid context isolated',config:{engine:'katex'},source:'x+1',context:[{source:'\\notARealCommand',input:'tex',display:false}],selector:'.katex'},
  {name:'KaTeX future definition stays future',config:{engine:'katex'},source:'\\future',context:[{source:'\\future',input:'tex',display:false},{source:'\\gdef\\future{LATE}',input:'tex',display:false}],contextIndex:0,error:true},
  {name:'MathJax forward reference',config:{engine:'mathjax',output:'html',accessibility:false},source:'\\eqref{e}',context:[{source:'\\eqref{e}',input:'tex',display:false},{source:'x\\tag{1}\\label{e}',input:'tex',display:true}],contextIndex:0,selector:'a[href="#mjx-eqn%3Ae"]'},
  {name:'Native menu zoom preference',config:{engine:'mathjax',output:'html',accessibility:false,menu:true},source:'x^2',selector:'mjx-container',action:['Math Settings','Zoom Factor','200%'],setting:'zscale',expected:'200%'},
  {name:'Native menu semantic export preference',config:{engine:'mathjax',output:'html',accessibility:false,menu:true},source:'x^2',selector:'mjx-container',action:['Math Settings','MathML/SVG has','Original as annotation'],setting:'semantics',expected:true},
  {name:'Native menu explorer preference',config:{engine:'mathjax',output:'html',accessibility:true,menu:true},source:'x^2',selector:'mjx-container',action:['Explorer','Highlight','Background','Red'],a11ySetting:'backgroundColor',expected:'Red'},
  {name:'Native menu changes output renderer',config:{engine:'mathjax',output:'html',accessibility:false,menu:true},source:'x^2',selector:'svg',action:['Math Settings','Math Renderer','SVG'],setting:'renderer',expected:'SVG'},
  {name:'Native menu changes speech language',config:{engine:'mathjax',output:'html',accessibility:true,menu:true},source:'x^2',selector:'[data-semantic-type]',action:['Speech','Language','French'],a11ySetting:'locale',expected:'fr'},
  {name:'Native menu enables enrichment',config:{engine:'mathjax',output:'html',accessibility:false,menu:true},source:'x^2',selector:'[data-semantic-type]',action:['Options','Semantic Enrichment'],setting:'enrich',expected:true},
  ...['mathjax','katex'].map(engine=>({name:`${engine} retains 128th preceding definition`,config:{engine,output:'html',accessibility:false},source:'\\shared',context:[...Array.from({length:128},(_,i)=>({source:`\\${engine==='katex'?'gdef':'def'}\\shared{${i+1}}`,input:'tex',display:false})),{source:'\\shared',input:'tex',display:false}],contextIndex:128,selector:engine==='katex'?'.katex':'mjx-container',mathmlIncludes:'128'})),
  ...['mathjax','katex'].map(engine=>({name:`${engine} isolates oversized preceding source`,config:{engine,output:'html',accessibility:false},source:'x+1',context:[{source:'z'.repeat(17000),input:'tex',display:false},{source:'x+1',input:'tex',display:false}],contextIndex:1,selector:engine==='katex'?'.katex':'mjx-container',mathmlIncludes:'1'})),
  {name:'KaTeX invalid retains source',config:{engine:'katex'},source:'\\notARealCommand',error:true},
];
let html=await readFile(resolve(output,'index.html'),'utf8');
html=html.replace('<script src="render.js"','<script src="fixture-client.js"></script><script src="render.js"');
await writeFile(resolve(output,'index.html'),html);
await writeFile(resolve(output,'fixture-client.js'),`const cases=${JSON.stringify(cases)}; const test=cases[Number(location.search.slice(1))];
let actionDone=false;window.NativeMath={postMessage:message=>{const data=JSON.parse(message);if(data.type==='ready') {
window.renderMath({v:1,generation:1,context:[],input:'tex',display:true,color:'#000000',fontSize:18,...test});
} else if(data.type==='result'||data.type==='error') {
if(test.action && data.type==='result' && !actionDone){actionDone=true;let entries=data.menu;let chosen;for(const label of test.action){chosen=entries?.find(item=>item.label===label);entries=chosen?.children;}if(!chosen){parent.postMessage({name:test.name,pass:false,error:'missing-menu-item',menu:data.menu},'*');return;}window.mathMenuAction({v:1,generation:1,id:chosen.id});return;}
const settingsPass=!test.action || (test.a11ySetting ? MathJax.startup.document.menu.getA11y(test.a11ySetting) : MathJax.startup.document.menu.settings[test.setting])===test.expected;

parent.postMessage({name:test.name,pass:test.error?data.type==='error':data.type==='result'&&settingsPass&&(!test.mathmlIncludes||data.formats?.mathml?.includes(test.mathmlIncludes))&&data.baseline>=0&&data.baseline<=data.height&&data.width<800&&!!document.querySelector(test.selector)&&(!test.reject||!document.querySelector(test.reject)),data,html:document.getElementById('math').innerHTML.slice(0,1000)},'*');
}}};`);
await writeFile(resolve(output,'fixture.html'),'<html><body><iframe style="width:800px;height:600px"></iframe><script src="fixture.js"></script></body></html>');
await writeFile(resolve(output,'fixture.js'),`window.results=[];let index=0;const frame=document.querySelector('iframe');let timer;function next(){if(index===${cases.length}){window.done=true;return;}frame.src='index.html?'+index;timer=setTimeout(()=>{results.push({name:${JSON.stringify(cases.map(c=>c.name))}[index],pass:false,error:'timeout'});index++;next();},10000);}window.addEventListener('message',e=>{if(e.source!==frame.contentWindow)return;clearTimeout(timer);results.push(e.data);index++;next();});next();`);
console.log(resolve(output,'fixture.html'));
