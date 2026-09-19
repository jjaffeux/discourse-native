export function setup(helper) {
 helper.registerOptions((options) => { options.features['fixture-mark'] = true; });
 helper.allowList(['mark[data-fixture]']);
 helper.registerPlugin(md => {
  md.inline.ruler.before('emphasis','fixture-mark',(state,silent)=> {
   if(state.src.slice(state.pos,state.pos+2)!=='==') return false;
   const end=state.src.indexOf('==',state.pos+2); if(end<0) return false;
   if(!silent) { const open=state.push('fixture_open','mark',1); open.attrSet('data-fixture','bundled'); const text=state.push('text','',0); text.content=state.src.slice(state.pos+2,end); state.push('fixture_close','mark',-1); }
   state.pos=end+2; return true;
  });
 });
}
