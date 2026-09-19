import { setup as upstream } from '../../vendor/plugins/discourse-events/assets/javascripts/discourse/lib/discourse-markdown/livestream-preview.js';

export function setup(helper) {
  // The legacy module explicitly checks the markdownIt flag on its helper.
  upstream(helper);
}
