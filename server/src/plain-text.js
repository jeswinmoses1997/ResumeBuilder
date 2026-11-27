// Some models return a document as nested objects or arrays despite being asked
// for a string. Flatten those into readable text.
export function toPlainText(value) {
  if (typeof value === 'string') return value;
  if (Array.isArray(value)) {
    return value.map(toPlainText).filter(Boolean).join('\n');
  }
  if (value && typeof value === 'object') {
    return Object.entries(value)
      .map(([key, item]) => {
        const text = toPlainText(item);
        return text ? `${key}\n${text}` : '';
      })
      .filter(Boolean)
      .join('\n\n');
  }
  return '';
}
