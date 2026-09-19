import escape from '../vendor/frontend/discourse/app/lib/escape.js';
const labels={
 en:{quote:'Quote',expand:'Expand',collapse:'Collapse','chat.quote.default_thread_title':'Thread','post.hidden_bidi_character':'Hidden bidirectional Unicode character'},
 fr:{quote:'Citation',expand:'Développer',collapse:'Réduire','chat.quote.default_thread_title':'Fil de discussion','post.hidden_bidi_character':'Caractère Unicode bidirectionnel masqué'},
 de:{quote:'Zitat',expand:'Erweitern',collapse:'Einklappen','chat.quote.default_thread_title':'Thread','post.hidden_bidi_character':'Verborgenes bidirektionales Unicode-Zeichen'},
 es:{quote:'Cita',expand:'Expandir',collapse:'Contraer','chat.quote.default_thread_title':'Hilo','post.hidden_bidi_character':'Carácter Unicode bidireccional oculto'},
};
let currentLocale='en';
export function setLocale(locale){currentLocale=locale || 'en';}
export function i18n(key,values={},locale=currentLocale) {
 if(key==='chat.quote.original_channel') return `<a href="${escape(values.channelLink || '')}">#${values.channel || ''}</a> · ${ {fr:'Canal d’origine',de:'Ursprünglicher Kanal',es:'Canal original'}[locale] || 'Original channel'}`;
 return labels[locale]?.[key] || labels.en[key] || escape(key.split('.').at(-1).replaceAll('_',' '));
}
export default {t:i18n};
