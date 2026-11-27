const PROVIDERS = {
  openai: {
    key: 'OPENAI_API_KEY',
    model: 'OPENAI_MODEL',
    defaultModel: 'gpt-4.1-mini',
    endpoint: 'https://api.openai.com/v1/chat/completions',
    protocol: 'openai',
  },
  anthropic: {
    key: 'ANTHROPIC_API_KEY',
    model: 'ANTHROPIC_MODEL',
    defaultModel: 'claude-sonnet-4-5',
    endpoint: 'https://api.anthropic.com/v1/messages',
    protocol: 'anthropic',
  },
  gemini: {
    key: 'GEMINI_API_KEY',
    model: 'GEMINI_MODEL',
    defaultModel: 'gemini-2.5-flash',
    endpoint: 'https://generativelanguage.googleapis.com/v1beta/models',
    protocol: 'gemini',
  },
  groq: {
    key: 'GROQ_API_KEY',
    model: 'GROQ_MODEL',
    defaultModel: 'openai/gpt-oss-120b',
    endpoint: 'https://api.groq.com/openai/v1/chat/completions',
    protocol: 'openai',
  },
};

const TASK_ORDER = {
  work_experience: 'AI_ORDER_WRITING',
  project: 'AI_ORDER_WRITING',
  tailor: 'AI_ORDER_STRUCTURED',
  job_match: 'AI_ORDER_STRUCTURED',
  documents: 'AI_ORDER_STRUCTURED',
  resume_extract: 'AI_ORDER_STRUCTURED',
};

const SYSTEM_PROMPT = `You are a careful professional resume editor. Use only facts supplied by the user. Never invent employers, responsibilities, skills, dates, degrees, achievements, numbers, or projects. If details are missing, ask concise follow-up questions and mark suggestions as unverified. Write in natural, concise professional language; proofread spelling, grammar, punctuation, and sentence flow; avoid clichés, inflated claims, and generic AI-sounding filler. Keep wording clear, specific, truthful, and suitable for applicant tracking systems. Do not claim to evade AI detectors or guarantee hiring outcomes. Return only valid JSON matching the requested shape.`;

export class ProviderError extends Error {
  constructor(message, status = 502, code = 'provider_error') {
    super(message);
    this.name = 'ProviderError';
    this.status = status;
    this.code = code;
  }
}

function providerOrder(task, env) {
  const setting = TASK_ORDER[task];
  if (!setting) {
    throw new ProviderError('Unsupported AI task.', 400, 'invalid_task');
  }

  const configured = (env[setting] || '')
    .split(',')
    .map((name) => name.trim().toLowerCase())
    .filter((name) => name in PROVIDERS);
  const order = configured.length
    ? configured
    : ['anthropic', 'openai', 'gemini', 'groq'];

  return [...new Set(order)].filter((name) => env[PROVIDERS[name].key]);
}

function responseText(provider, body) {
  if (provider === 'anthropic') {
    return body.content?.find((item) => item.type === 'text')?.text;
  }
  if (provider === 'gemini') {
    return body.candidates?.[0]?.content?.parts
      ?.map((part) => part.text || '')
      .join('');
  }
  return body.choices?.[0]?.message?.content;
}

function extractJson(text) {
  if (typeof text !== 'string') {
    throw new ProviderError('The AI provider returned no text.', 502);
  }
  const cleaned = text.trim().replace(/^```(?:json)?\s*|\s*```$/g, '');
  try {
    return JSON.parse(cleaned);
  } catch {
    const start = cleaned.indexOf('{');
    const end = cleaned.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw new ProviderError('The AI response was not valid JSON.', 502);
    }
    try {
      return JSON.parse(cleaned.slice(start, end + 1));
    } catch {
      throw new ProviderError('The AI response was not valid JSON.', 502);
    }
  }
}

async function callProvider(name, prompt, env, fetchImpl) {
  const provider = PROVIDERS[name];
  const apiKey = env[provider.key];
  const model = env[provider.model] || provider.defaultModel;
  let url = provider.endpoint;
  let headers = { 'content-type': 'application/json' };
  let body;

  if (provider.protocol === 'anthropic') {
    headers = {
      ...headers,
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    };
    body = {
      model,
      max_tokens: 8000,
      system: SYSTEM_PROMPT,
      messages: [{ role: 'user', content: prompt }],
    };
  } else if (provider.protocol === 'gemini') {
    url = `${url}/${encodeURIComponent(model)}:generateContent`;
    headers['x-goog-api-key'] = apiKey;
    body = {
      systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: {
        responseMimeType: 'application/json',
        maxOutputTokens: 8000,
      },
    };
  } else {
    headers.authorization = `Bearer ${apiKey}`;
    body = {
      model,
      temperature: 0.2,
      response_format: { type: 'json_object' },
      ...(name === 'groq'
        ? { max_tokens: 8000 }
        : { max_completion_tokens: 8000 }),
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        { role: 'user', content: prompt },
      ],
    };
  }

  let response;
  try {
    response = await fetchImpl(url, {
      method: 'POST',
      headers,
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(45_000),
    });
  } catch {
    throw new ProviderError('The AI provider could not be reached.', 502);
  }

  if (!response.ok) {
    const status = response.status;
    if (status === 401 || status === 403) {
      throw new ProviderError('The configured AI provider rejected its key.', 502);
    }
    if (status === 429) {
      throw new ProviderError('The AI provider is rate-limiting requests.', 429);
    }
    throw new ProviderError(
      `The AI provider returned HTTP ${status}.`,
      status >= 500 ? 502 : 400,
    );
  }

  let result;
  try {
    result = await response.json();
  } catch {
    throw new ProviderError('The AI provider returned an unreadable response.');
  }
  return extractJson(responseText(name, result));
}

export function createProviderRouter({
  env = process.env,
  fetchImpl = globalThis.fetch,
  logger = console,
} = {}) {
  return {
    configuredProviders() {
      return Object.keys(PROVIDERS).filter((name) => env[PROVIDERS[name].key]);
    },

    async generate(task, input) {
      const order = providerOrder(task, env);
      if (!order.length) {
        throw new ProviderError(
          'No AI provider is configured. Add a provider key to server/.env.',
          503,
          'no_provider_configured',
        );
      }

      const prompt = `Task: ${task}\nReturn a JSON object appropriate for this task.\nUser-provided information:\n${JSON.stringify(input)}`;
      const failures = [];

      for (const name of order) {
        try {
          const output = await callProvider(name, prompt, env, fetchImpl);
          return { provider: name, output };
        } catch (error) {
          if (!(error instanceof ProviderError)) throw error;
          failures.push({ provider: name, error });
          logger.warn?.(`AI provider ${name} failed (${error.code}).`);
          if (error.status === 400 && error.code === 'invalid_task') throw error;
        }
      }

      const last = failures.at(-1)?.error;
      throw new ProviderError(
        last?.message || 'All configured AI providers failed.',
        last?.status || 502,
        'all_providers_failed',
      );
    },
  };
}
