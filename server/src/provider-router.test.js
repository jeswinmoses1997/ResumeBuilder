import test from 'node:test';
import assert from 'node:assert/strict';
import { createProviderRouter } from './provider-router.js';

const silentLogger = { warn() {} };

test('routes to the first configured provider and parses its JSON result', async () => {
  const calls = [];
  const router = createProviderRouter({
    env: {
      ANTHROPIC_API_KEY: 'test-key',
      AI_ORDER_WRITING: 'anthropic,openai',
    },
    logger: silentLogger,
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return new Response(
        JSON.stringify({
          content: [{ type: 'text', text: '{"draft":"Draft","questions":[]}' }],
        }),
        { status: 200 },
      );
    },
  });

  const result = await router.generate('work_experience', { jobTitle: 'Designer' });
  assert.equal(result.provider, 'anthropic');
  assert.equal(result.output.draft, 'Draft');
  assert.equal(calls.length, 1);
  assert.match(calls[0].url, /anthropic\.com/);
});

test('returns a clear configuration error when there are no provider keys', async () => {
  const router = createProviderRouter({ env: {}, logger: silentLogger });
  await assert.rejects(
    router.generate('documents', {}),
    { code: 'no_provider_configured', status: 503 },
  );
});

test('tries the next configured provider after an upstream failure', async () => {
  const tried = [];
  const router = createProviderRouter({
    env: {
      ANTHROPIC_API_KEY: 'anthropic-key',
      OPENAI_API_KEY: 'openai-key',
      AI_ORDER_WRITING: 'anthropic,openai',
    },
    logger: silentLogger,
    fetchImpl: async (url) => {
      tried.push(url);
      if (url.includes('anthropic.com')) {
        return new Response('{}', { status: 503 });
      }
      return new Response(
        JSON.stringify({
          choices: [{ message: { content: '{"draft":"ok","questions":[]}' } }],
        }),
        { status: 200 },
      );
    },
  });

  const result = await router.generate('work_experience', { jobTitle: 'Designer' });
  assert.equal(result.provider, 'openai');
  assert.equal(tried.length, 2);
});

test('routes JD tailoring through the structured-task provider order', async () => {
  const calls = [];
  const router = createProviderRouter({
    env: {
      GEMINI_API_KEY: 'gemini-key',
      OPENAI_API_KEY: 'openai-key',
      AI_ORDER_STRUCTURED: 'gemini,openai',
    },
    logger: silentLogger,
    fetchImpl: async (url) => {
      calls.push(url);
      return new Response(
        JSON.stringify({
          candidates: [{
            content: {
              parts: [{
                text: JSON.stringify({
                  matchedSkills: [],
                  suggestedSkills: [],
                  experienceDrafts: [],
                  recommendations: [],
                  questions: [],
                }),
              }],
            },
          }],
        }),
        { status: 200 },
      );
    },
  });

  const result = await router.generate('tailor', { jobDescription: 'designer' });
  assert.equal(result.provider, 'gemini');
  assert.equal(calls.length, 1);
  assert.match(calls[0], /generativelanguage\.googleapis\.com/);
});

test('routes job-match estimates through the configured structured provider', async () => {
  const calls = [];
  const router = createProviderRouter({
    env: {
      GROQ_API_KEY: 'test-key',
      AI_ORDER_STRUCTURED: 'groq',
    },
    logger: silentLogger,
    fetchImpl: async (url) => {
      calls.push(url);
      return new Response(
        JSON.stringify({
          choices: [{
            message: {
              content: JSON.stringify({ matches: [] }),
            },
          }],
        }),
        { status: 200 },
      );
    },
  });

  const result = await router.generate('job_match', { jobs: [] });
  assert.equal(result.provider, 'groq');
  assert.deepEqual(result.output, { matches: [] });
  assert.equal(calls.length, 1);
  assert.match(calls[0], /api\.groq\.com/);
});
