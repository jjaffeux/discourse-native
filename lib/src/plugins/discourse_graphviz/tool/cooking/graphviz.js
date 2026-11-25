import { setup as upstream } from './upstream-graphviz.js';

export function setup(helper, context) {
  upstream({
    markdownIt: true,
    allowList: values => helper.allowList(values),
    registerOptions: callback => helper.registerOptions(options => callback(options, context.settings || {})),
    registerPlugin: callback => helper.registerPlugin(callback),
  });
}
