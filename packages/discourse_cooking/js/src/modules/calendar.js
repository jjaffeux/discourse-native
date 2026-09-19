import { setup as upstream } from '../../vendor/plugins/discourse-events/assets/javascripts/discourse/lib/discourse-markdown/discourse-calendar.js';

export function setup(helper, context) {
  upstream({
    allowList: values => helper.allowList(values),
    registerOptions: callback => helper.registerOptions(options => callback(options, context.settings || {})),
    registerPlugin: callback => helper.registerPlugin(callback),
  });
}
