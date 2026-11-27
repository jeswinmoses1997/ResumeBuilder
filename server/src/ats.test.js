import test from 'node:test';
import assert from 'node:assert/strict';
import { scoreKeywordCoverage } from './ats.js';

test('scores distinct job keywords and reports coverage transparently', () => {
  const result = scoreKeywordCoverage(
    'Build React applications with TypeScript and testing',
    'Built React applications using TypeScript',
  );

  assert.equal(result.score, 60);
  assert.deepEqual(result.matchedKeywords, ['applications', 'react', 'typescript']);
  assert.deepEqual(result.missingKeywords, ['build', 'testing']);
  assert.match(result.message, /not an ATS vendor score/);
});

test('does not score when the job description or resume is missing', () => {
  assert.equal(scoreKeywordCoverage('', 'React').score, null);
});
