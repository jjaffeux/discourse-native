import { setup as upstream } from '../../vendor/plugins/discourse-math/assets/javascripts/lib/discourse-markdown/discourse-math.js';

export function setup(helper, context) {
  upstream({
    markdownIt: true,
    allowList: values => helper.allowList(values),
    registerOptions: callback => helper.registerOptions(options => {
      callback(options, context.settings || {});
      const enabled = ['math', 'asciimath', 'enable_latex_delimiters'].filter(name => options.features[name]);
      if (options.featuresOverride) options.featuresOverride.push(...enabled);
    }),
    registerPlugin: callback => helper.registerPlugin(callback),
  });
}
