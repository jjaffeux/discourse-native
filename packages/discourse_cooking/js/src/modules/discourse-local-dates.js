import moment from 'moment-timezone';
import 'moment/min/locales';
import { setup as upstream } from '../../vendor/plugins/discourse-local-dates/assets/javascripts/lib/discourse-markdown/discourse-local-dates.js';

export function setup(helper, context, api) {
  api.onCleanup(()=>{moment.locale('en');moment.tz.setDefault();moment.now=()=>0;});
  helper.allowList(['span[data-range]']);
  upstream({
    allowList: values => helper.allowList(values),
    registerOptions: callback => helper.registerOptions(options => callback(options, context.settings || {})),
    registerPlugin: callback => helper.registerPlugin(md => {
      // Every actual parse resets all mutable date defaults from frozen input.
      md.core.ruler.before('normalize', 'frozen-local-date-context', () => {
        moment.locale('en');
        moment.locale(api.context.locale || 'en');
        moment.tz.setDefault('Etc/UTC');
        moment.now = () => api.context.asOfEpochMilliseconds || 0;
      });
      callback(md);
    }),
  });
}
