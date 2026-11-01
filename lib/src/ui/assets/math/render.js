'use strict';
(() => {
  const protocol = 1;
  let generation = -1;
  let configured = null;
  const root = document.getElementById('math');
  const send = message => window.NativeMath?.postMessage(JSON.stringify({v:protocol,...message}));
  const load = src => new Promise((resolve,reject) => {
    const script = document.createElement('script');
    script.src = src; script.onload = resolve; script.onerror = reject;
    document.head.append(script);
  });
  const safeHref = value => typeof value === 'string' && value.length <= 2048 &&
    !/[\u0000-\u0020<>"'\\]/.test(value) && !value.startsWith('//') &&
    (!/^[a-z][a-z0-9+.-]*:/i.test(value) || /^(https?:|mailto:)/i.test(value));
  const safeId = value => typeof value === 'string' && /^[A-Za-z_][A-Za-z0-9_:.-]*$/.test(value);
  async function configure(config) {
    const identity = JSON.stringify(config);
    if (configured) { if (configured !== identity) throw Error('configuration'); return; }
    configured = identity;
    if (config.engine === 'katex') {
      await load('katex/dist/katex.min.js');
      await load('katex/dist/contrib/mhchem.min.js');
      await load('katex/dist/contrib/copy-tex.min.js');
      return;
    }
    if (config.accessibility) {
      await load('speech-maps.js');
      await load('speech-worker-source.js');
      window.SREfeature = {custom: locale => Promise.resolve(window.mathSpeechMaps[locale])};
    }
    const output = config.output === 'svg' ? 'svg' : 'chtml';
    window.MathJax = {
      startup:{typeset:false,ready() {
        MathJax.startup.defaultReady();
        if (config.accessibility) MathJax.startup.adaptor.createWorker = async listener => {
          const prefix = 'self.maps="";const maps='+JSON.stringify(window.mathSpeechMaps)+';self.fetch=path=>Promise.resolve({json:()=>Promise.resolve(maps[path.split("/").pop().replace(/\\.json$/,"" )])});';
          const url = URL.createObjectURL(new Blob([prefix,window.mathSpeechWorkerSource],{type:'text/javascript'}));
          const worker = new Worker(url);
          worker.onmessage = listener;
          URL.revokeObjectURL(url);
          return worker;
        };
      }},
      loader:{load:['ui/safe','input/asciimath'], paths:{mathjax:'mathjax', font:'newcm', sre:'mathjax/sre'}},
      output:{font:'mathjax-newcm', fontPath:'newcm'},
      chtml:{fontURL:'newcm/chtml/woff2'},
      svg:{fontCache:'local'},
      tex:{inlineMath:[['\\(','\\)']],displayMath:[['\\[','\\]']]},
      asciimath:{delimiters:[['%','%']]},
      options:{enableMenu:false, worker:{path:new URL('mathjax/sre',location.href).href,maps:new URL('mathjax/sre/mathmaps',location.href).href}, enableEnrichment:config.accessibility,
        enableExplorer:config.accessibility, enableAssistiveMml:config.accessibility,
        menuOptions:{settings:{enrich:config.accessibility}}},
      sre:{json:'mathjax/sre/mathmaps'},
    };
    await load(`mathjax/tex-mml-${output}.js`);
    await MathJax.startup.promise;
  }
  window.renderMath = async request => {
    if (request.v !== protocol || !Number.isSafeInteger(request.generation) ||
        typeof request.source !== 'string' || request.source.length > 16384 ||
        !Array.isArray(request.context) || request.context.length > 128 ||
        JSON.stringify(request).length > 131072) return;
    generation = request.generation;
    const current = () => generation === request.generation;
    try {
      await configure(request.config);
      if (!current()) return;
      root.replaceChildren();
      root.className = request.display ? 'display' : '';
      root.style.color = request.color;
      root.style.fontSize = `${Math.max(8,Math.min(96,request.fontSize))}px`;
      if (request.config.engine === 'katex') {
        if (request.input !== 'tex') throw Error('unsupported-input');
        const macros = {'\\eqref':'\\href{###1}{(\\text{#1})}', '\\ref':'\\href{###1}{\\text{#1}}', '\\label':'\\htmlId{#1}{}'};
        const options = {macros,displayMode:request.display,throwOnError:true,maxExpand:1000,maxSize:20,
          trust:context => context.command === '\\href' ? safeHref(context.url) :
            context.command === '\\htmlId' && safeId(context.url || context.text || context.id)};
        for (const expression of request.context) {
          if (expression.input === 'tex') katex.renderToString(expression.source, {...options,displayMode:expression.display});
        }
        katex.render(request.source,root,options);
      } else {
        MathJax.typesetClear();
        MathJax.texReset();
        const expressions = request.contextIndex == null ? [...request.context, {source:request.source,input:request.input,display:request.display}] : request.context;
        const selected = request.contextIndex == null ? expressions.length-1 : request.contextIndex;
        for (const [index, expression] of expressions.entries()) {
          const element = document.createElement('span');
          element.textContent = expression.input === 'ascii' ? `%${expression.source}%` :
            expression.display ? `\\[${expression.source}\\]` : `\\(${expression.source}\\)`;
          root.append(element);
          if (index !== selected) element.className = 'context';
        }
        await MathJax.typesetPromise([root]);
      }
      await document.fonts.ready;
      if (!current()) return;
      if (root.querySelector('mjx-merror,[data-mjx-error]')) throw Error('invalid-source');
      if (root.innerHTML.length > 2000000) throw Error('output-limit');
      const bounds = root.getBoundingClientRect();
      if (bounds.width > 16384 || bounds.height > 4096) throw Error('size-limit');
      const baselineMarker = document.createElement('span');
      baselineMarker.style.cssText = 'display:inline-block;width:0;height:0';
      root.append(baselineMarker);
      const baseline = request.display ? bounds.height : Math.min(bounds.height,baselineMarker.getBoundingClientRect().top-bounds.top);
      baselineMarker.remove();
      const target = [...root.children].find(element => !element.classList.contains('context')) || root;
      let mathml = target.querySelector('math')?.outerHTML;
      if (request.config.engine === 'mathjax') {
        const item = [...MathJax.startup.document.math].find(item => target.contains(item.typesetRoot));
        if (item) mathml = MathJax.startup.document.menu?.toMML(item);
      }
      const formats = {mathml, svg:target.querySelector('svg')?.outerHTML,
        speech:target.querySelector('[aria-label]')?.getAttribute('aria-label'),
        braille:target.querySelector('[data-semantic-braille]')?.getAttribute('data-semantic-braille')};
      for (const name of Object.keys(formats)) if (!formats[name] || formats[name].length > 65536) delete formats[name];
      send({type:'result',generation,width:Math.ceil(bounds.width),height:Math.ceil(bounds.height),baseline,formats});
    } catch (_) { if (current()) send({type:'error',generation}); }
  };
  document.addEventListener('click', event => {
    const anchor = event.target.closest('a');
    if (anchor) { event.preventDefault(); if (safeHref(anchor.getAttribute('href'))) send({type:'link',generation,url:anchor.getAttribute('href')}); }
    else send({type:'activate',generation});
  });
  document.addEventListener('contextmenu', event => {event.preventDefault();send({type:'menu',generation,x:event.clientX,y:event.clientY});});
  send({type:'ready'});
})();
