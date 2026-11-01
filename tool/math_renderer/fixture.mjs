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
  {name:'KaTeX invalid retains source',config:{engine:'katex'},source:'\\notARealCommand',error:true},
];
let html=await readFile(resolve(output,'index.html'),'utf8');
html=html.replace('<script src="render.js"','<script src="fixture-client.js"></script><script src="render.js"');
await writeFile(resolve(output,'index.html'),html);
await writeFile(resolve(output,'fixture-client.js'),`const cases=${JSON.stringify(cases)}; const test=cases[Number(location.search.slice(1))];
window.NativeMath={postMessage:message=>{const data=JSON.parse(message);if(data.type==='ready') {
window.renderMath({v:1,generation:1,context:[],input:'tex',display:true,color:'#000000',fontSize:18,...test});
} else if(data.type==='result'||data.type==='error') {
parent.postMessage({name:test.name,pass:test.error?data.type==='error':data.type==='result'&&!!document.querySelector(test.selector)&&(!test.reject||!document.querySelector(test.reject)),data,html:document.getElementById('math').innerHTML.slice(0,1000)},'*');
}}};`);
await writeFile(resolve(output,'fixture.html'),'<html><body><iframe style="width:800px;height:600px"></iframe><script src="fixture.js"></script></body></html>');
await writeFile(resolve(output,'fixture.js'),`window.results=[];let index=0;const frame=document.querySelector('iframe');let timer;function next(){if(index===${cases.length}){window.done=true;return;}frame.src='index.html?'+index;timer=setTimeout(()=>{results.push({name:${JSON.stringify(cases.map(c=>c.name))}[index],pass:false,error:'timeout'});index++;next();},10000);}window.addEventListener('message',e=>{if(e.source!==frame.contentWindow)return;clearTimeout(timer);results.push(e.data);index++;next();});next();`);
console.log(resolve(output,'fixture.html'));
