import { setup as upstream } from '../../vendor/plugins/checklist/assets/javascripts/lib/discourse-markdown/checklist.js';

export function setup(helper, context) {
  upstream({
    allowList: values => helper.allowList(values),
    registerPlugin: callback => helper.registerPlugin(callback),
    registerOptions: callback => helper.registerOptions(options => callback(options, context.settings || {})),
  });
}
