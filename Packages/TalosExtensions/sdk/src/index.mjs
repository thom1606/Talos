/** Describes native Talos controls; action code never renders the settings window. */
export const settings = Object.freeze({
  text: (id, label, options = {}) => ({ ...options, id, label, type: 'text' }),
  password: (id, label, options = {}) => ({ ...options, id, label, type: 'password' }),
  number: (id, label, options = {}) => ({ ...options, id, label, type: 'number' }),
  toggle: (id, label, options = {}) => ({ ...options, id, label, type: 'toggle' }),
  select: (id, label, choices, options = {}) => ({
    ...options,
    id,
    label,
    choices,
    type: 'select',
  }),
});

/** English is the fallback; the host passes the user's preferred language. */
export function localize(value, language = 'en') {
  if (typeof value === 'string') return value;
  return value?.[language] ?? value?.[language.split('-')[0]] ?? value?.en ?? '';
}

export function defineExtension(extension) {
  return extension;
}
