'use strict';
(() => {
  let commands = new Map();
  const current = () => window.MathJax?.startup?.document?.menu;
  const send = message => window.NativeMath?.postMessage(JSON.stringify({v:1,...message}));
  const selected = () => {
    const target = [...document.getElementById('math').children].find(node=>!node.classList.contains('context'));
    return [...MathJax.startup.document.math].find(item=>target?.contains(item.typesetRoot));
  };
  window.mathMenuSnapshot = () => {
    const owner = current(), item = owner && selected();
    if (!item) return [];
    const menu=owner.menu;
    menu.mathItem=item;
    for (const method of ['getOriginalMenu','getSemanticsMenu','getSpeechMenu','getBrailleMenu','getSvgMenu','getErrorMessage','dynamicSubmenus']) menu[method]();
    commands = new Map();
    function entries(items,path=[],depth=0) {
      if(depth>8) return [];
      return items.filter(item=>!item.isHidden()).slice(0,200).map((item,index)=>{
        const id=[...path,index].join('.');
        commands.set(id,item);
        const result={id,type:item.type,label:String(item.content || '').trim().slice(0,160),disabled:!!item.disabled};
        if(item.variable) {
          const value=item.variable.getValue();
          result.checked=item.type==='checkbox' ? !!value : value===item.id;
          if(item.type==='slider') result.value=Number(value);
        }
        if(item.submenu) result.children=entries(item.submenu.items,[...path,index],depth+1);
        return result;
      });
    }
    return entries(menu.items);
  };
  window.mathMenuAction = async request => {
    const owner=current(), item=commands.get(request.id);
    const generation=window.mathCurrentRequest?.generation;
    if(request.v!==1 || request.generation!==generation || !owner || !item || item.disabled || item.isHidden()) return;
    owner.menu.mathItem=selected();
    try {
      if(item.type==='checkbox') item.variable.setValue(!item.variable.getValue());
      else if(item.type==='radio' || item.type==='radioCompare') {
        if(item.id==='CHTML'||item.id==='SVG') {owner.settings.renderer=item.id;await owner.setRenderer(item.id);}
        else item.variable.setValue(item.id);
      }
      else if(item.type==='slider' && Number.isFinite(request.value)) item.variable.setValue(Math.max(0,Math.min(100,request.value)));
      else if(item.type==='command') {
        const ancestors=[];
        let menu=item.menu;
        while(menu?.anchor) {ancestors.push(menu.anchor.id);menu=menu.anchor.menu;}
        const math=owner.menu.mathItem;
        let value;
        switch(item.id) {
          case 'MathMLcode': value=owner.toMML(math);break;
          case 'Original': value=math.math;break;
          case 'Speech': value=math.outputData.speech;break;
          case 'Braille': value=math.outputData.braille;break;
          case 'SVG': value=await owner.toSVG(math);break;
          case 'Error': value=owner.menu.errorMsg;break;
          case 'ZoomNow': send({type:'zoom',generation,scale:parseFloat(owner.settings.zscale)/100});return;
          case 'Scale': send({type:'scale',generation,scale:owner.settings.scale});return;
          case 'Reset': owner.resetDefaults();break;
          case 'About': value=`MathJax ${MathJax.version}\nApache License 2.0\nhttps://www.mathjax.org`;break;
          case 'Help': value='Use Tab to focus an expression. Enter starts exploration; arrow keys move through its structure, and Escape leaves exploration. Native menu preferences apply to this expression document.\nhttps://docs.mathjax.org/en/latest/basic/accessibility.html';break;
          default: {
            let node=math.root;
            while(node && !node.isKind('semantics') && !node.isToken && node.childNodes.length===1) node=node.childNodes[0];
            const encodings=owner.options.annotationTypes[item.id] || [];
            const annotation=node?.childNodes.find(child=>child.isKind('annotation') && encodings.includes(child.attributes.get('encoding')));
            value=annotation?.childNodes.map(child=>child.toString()).join('');
          }
        }
        if(typeof value==='string' && value.length<=65536) send({type:'menuText',generation,label:item.content,text:value,copy:ancestors.some(id=>id==='Copy'||id==='CopyAnnotation')});
      }
      await owner.loadingPromise;
      await MathJax.startup.document.whenReady(()=>Promise.resolve());
      await document.fonts.ready;
      await window.mathPublish?.();
    } catch (_) { send({type:'menuFailed',generation}); }
  };
  window.mathMenuScale = async request => {
    if(request.generation!==window.mathCurrentRequest?.generation || !Number.isFinite(request.value))return;
    current()?.menu.pool.lookup('scale').setValue(Math.max(.5,Math.min(4,request.value)));
    await MathJax.startup.document.whenReady(()=>Promise.resolve());
    await window.mathPublish?.();
  };
})();
