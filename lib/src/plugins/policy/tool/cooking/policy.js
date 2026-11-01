import { setup as upstream } from './upstream-policy.js';

export function setup(helper, context) {
  upstream({
    allowList: values => helper.allowList(values),
    registerOptions: callback => helper.registerOptions(options => callback(options, context.settings || {})),
    registerPlugin: callback => helper.registerPlugin(callback),
  });
}
