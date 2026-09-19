import { setup as upstream } from '../../vendor/plugins/poll/assets/javascripts/lib/discourse-markdown/poll.js';

export function setup(helper, context) {
  upstream({
    allowList: values => helper.allowList(values),
    registerOptions: callback => helper.registerOptions(options => callback(options, context.settings || {})),
    registerPlugin: callback => helper.registerPlugin(callback),
  });
}
