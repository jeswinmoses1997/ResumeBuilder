import test from 'node:test';
import assert from 'node:assert/strict';
import { toPlainText } from './plain-text.js';

test('flattens nested AI output into readable text', () => {
  assert.equal(toPlainText('Hello'), 'Hello');
  assert.equal(
    toPlainText({ Questions: { 'Why this role?': 'I like it.' }, Tips: ['A', 'B'] }),
    'Questions\nWhy this role?\nI like it.\n\nTips\nA\nB',
  );
  assert.equal(toPlainText(undefined), '');
});
