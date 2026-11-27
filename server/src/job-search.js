export class JobSearchError extends Error {
  constructor(message, status = 502, code = 'job_search_error') {
    super(message);
    this.name = 'JobSearchError';
    this.status = status;
    this.code = code;
  }
}

const jobicyGeoByCountry = {
  au: 'australia',
  at: 'austria',
  ar: 'argentina',
  be: 'belgium',
  bg: 'bulgaria',
  br: 'brazil',
  ca: 'canada',
  cn: 'china',
  cr: 'costa-rica',
  hr: 'croatia',
  cy: 'cyprus',
  cz: 'czechia',
  dk: 'denmark',
  ee: 'estonia',
  fi: 'finland',
  fr: 'france',
  de: 'germany',
  gr: 'greece',
  hk: 'hong-kong',
  hu: 'hungary',
  ie: 'ireland',
  il: 'israel',
  it: 'italy',
  jp: 'japan',
  lv: 'latvia',
  lt: 'lithuania',
  my: 'malaysia',
  mx: 'mexico',
  nl: 'netherlands',
  nz: 'new-zealand',
  no: 'norway',
  ph: 'philippines',
  pl: 'poland',
  pt: 'portugal',
  ro: 'romania',
  rs: 'serbia',
  sg: 'singapore',
  sk: 'slovakia',
  si: 'slovenia',
  kr: 'south-korea',
  es: 'spain',
  se: 'sweden',
  ch: 'switzerland',
  th: 'thailand',
  tr: 'turkiye',
  ua: 'ukraine',
  ae: 'united-arab-emirates',
  gb: 'uk',
  us: 'usa',
  vn: 'vietnam',
  in: 'apac',
};
const jobicyTitleStopWords = new Set([
  'associate',
  'director',
  'entry',
  'intern',
  'junior',
  'lead',
  'level',
  'manager',
  'principal',
  'senior',
  'specialist',
  'staff',
]);

let lastJobicyRequestAt = 0;
let jobicyRequestQueue = Promise.resolve();

function text(value, maxLength = 4000) {
  return typeof value === 'string' ? value.slice(0, maxLength) : '';
}

function plainText(value, maxLength = 4000) {
  return text(value, maxLength)
    .replace(/<[^>]*>/g, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/\s+/g, ' ')
    .trim();
}

function safePostingUrl(value) {
  try {
    const url = new URL(value);
    if (!['http:', 'https:'].includes(url.protocol)) return '';
    url.protocol = 'https:';
    return url.toString();
  } catch {
    return '';
  }
}

function amount(value) {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0
    ? value
    : null;
}

function normalizeJob(job, countryCode) {
  if (!job || typeof job !== 'object' || job.id == null) return null;
  const salaryMin = amount(job.salary_min);
  const salaryMax = amount(job.salary_max);
  return {
    id: String(job.id),
    title: plainText(job.title),
    company: plainText(job.company?.display_name) || 'Company not listed',
    location: plainText(job.location?.display_name),
    description: plainText(job.description, 12_000),
    postingUrl: safePostingUrl(job.redirect_url),
    salaryMin,
    salaryMax,
    salaryCurrency: text(job.salary_currency, 8) || null,
    salaryIsPredicted: job.salary_is_predicted === 1 ||
      job.salary_is_predicted === true,
    source: 'Adzuna',
    countryCode,
    createdAt: text(job.created, 40),
    contractType: plainText(job.contract_type),
    contractTime: plainText(job.contract_time),
  };
}

function normalizeJobicyJob(job, countryCode) {
  if (!job || typeof job !== 'object' || job.id == null) return null;
  return {
    id: `jobicy-${job.id}`,
    title: plainText(job.jobTitle),
    company: plainText(job.companyName) || 'Company not listed',
    location: plainText(job.jobGeo),
    description: plainText(job.jobDescription || job.jobExcerpt, 12_000),
    postingUrl: safePostingUrl(job.url),
    salaryMin: amount(job.salaryMin),
    salaryMax: amount(job.salaryMax),
    salaryCurrency: text(job.salaryCurrency, 8) || null,
    salaryIsPredicted: false,
    source: 'Jobicy',
    countryCode,
    createdAt: text(job.pubDate, 40),
    contractType: Array.isArray(job.jobType)
      ? job.jobType.map((value) => plainText(value, 80)).join(', ')
      : '',
    contractTime: '',
  };
}

function titleRelevance(jobTitle, query) {
  const tokens = [...new Set(
    query
      .toLowerCase()
      .match(/[a-z0-9+#]+/g) ?? [],
  )].filter(
    (token) => token.length > 1 && !jobicyTitleStopWords.has(token),
  );
  const title = jobTitle.toLowerCase();
  return tokens.filter((token) => title.includes(token)).length;
}

function validateSearchInput({ countryCode, query, locations, limit }) {
  if (typeof countryCode !== 'string' || !/^[a-z]{2}$/.test(countryCode)) {
    throw new JobSearchError('Use a valid two-letter country code.', 400, 'invalid_country');
  }
  if (typeof query !== 'string' || !query.trim() || query.length > 200) {
    throw new JobSearchError(
      'Enter a job title or search terms under 200 characters.',
      400,
      'invalid_job_query',
    );
  }
  if (!Number.isInteger(limit) || limit < 1 || limit > 20) {
    throw new JobSearchError(
      'The job result limit must be between 1 and 20.',
      400,
      'invalid_result_limit',
    );
  }
  if (!Array.isArray(locations) || locations.length > 5) {
    throw new JobSearchError(
      'Search up to five locations at a time.',
      400,
      'invalid_job_locations',
    );
  }
  const cleanLocations = [
    ...new Set(
      locations
        .filter((location) => typeof location === 'string')
        .map((location) => location.trim())
        .filter(Boolean),
    ),
  ];
  if (cleanLocations.some((location) => location.length > 120)) {
    throw new JobSearchError(
      'Each job location must be under 120 characters.',
      400,
      'invalid_job_locations',
    );
  }
  return {
    countryCode,
    query: query.trim(),
    locations: cleanLocations,
    limit,
  };
}

async function respectJobicyRateLimit() {
  let release;
  const turn = new Promise((resolve) => {
    release = resolve;
  });
  const previous = jobicyRequestQueue;
  jobicyRequestQueue = previous.then(() => turn);
  await previous;

  const delay = Math.max(0, lastJobicyRequestAt + 1000 - Date.now());
  if (delay > 0) {
    await new Promise((resolve) => setTimeout(resolve, delay));
  }
  lastJobicyRequestAt = Date.now();
  release();
}

async function fetchLocation({
  appId,
  appKey,
  countryCode,
  query,
  location,
  resultsPerPage,
  fetchImpl,
}) {
  const url = new URL(
    `https://api.adzuna.com/v1/api/jobs/${countryCode}/search/1`,
  );
  url.searchParams.set('app_id', appId);
  url.searchParams.set('app_key', appKey);
  url.searchParams.set('results_per_page', String(resultsPerPage));
  url.searchParams.set('what', query);
  url.searchParams.set('content-type', 'application/json');
  url.searchParams.set('sort_by', 'relevance');
  if (location) url.searchParams.set('where', location);

  let response;
  try {
    response = await fetchImpl(url, {
      headers: { accept: 'application/json' },
      signal: AbortSignal.timeout(15_000),
    });
  } catch {
    throw new JobSearchError('The job search provider could not be reached.');
  }
  if (!response.ok) {
    if (response.status === 401 || response.status === 403) {
      throw new JobSearchError(
        'Adzuna rejected its configured API credentials.',
        502,
        'job_search_credentials_rejected',
      );
    }
    if (response.status === 429) {
      throw new JobSearchError(
        'Adzuna is rate-limiting job searches. Try again later.',
        429,
        'job_search_rate_limited',
      );
    }
    throw new JobSearchError(
      `Adzuna returned HTTP ${response.status} for this search.`,
      502,
    );
  }

  let result;
  try {
    result = await response.json();
  } catch {
    throw new JobSearchError('Adzuna returned an unreadable response.');
  }
  if (!Array.isArray(result?.results)) {
    throw new JobSearchError('Adzuna returned an invalid job list.');
  }
  return result.results
    .map((job) => normalizeJob(job, countryCode))
    .filter((job) => job && job.title && job.postingUrl);
}

export async function searchAdzunaJobs({
  env = process.env,
  fetchImpl = globalThis.fetch,
  countryCode,
  query,
  locations = [],
  limit = 20,
}) {
  const { query: cleanQuery, locations: cleanLocations } = validateSearchInput({
    countryCode,
    query,
    locations,
    limit,
  });
  const appId = env.ADZUNA_APP_ID;
  const appKey = env.ADZUNA_APP_KEY;
  if (!appId || !appKey) {
    throw new JobSearchError(
      'Job search is not configured. Add ADZUNA_APP_ID and ADZUNA_APP_KEY to server/.env.',
      503,
      'job_search_not_configured',
    );
  }
  const searchLocations = cleanLocations.length ? cleanLocations : [''];
  const perLocation = Math.min(
    20,
    Math.ceil(limit / searchLocations.length),
  );
  const groups = await Promise.all(
    searchLocations.map((location) =>
      fetchLocation({
        appId,
        appKey,
        countryCode,
        query: cleanQuery,
        location,
        resultsPerPage: perLocation,
        fetchImpl,
      }),
    ),
  );
  const uniqueJobs = new Map();
  for (const job of groups.flat()) {
    if (!uniqueJobs.has(job.id)) uniqueJobs.set(job.id, job);
  }
  return [...uniqueJobs.values()].slice(0, limit);
}

export async function searchJobicyJobs({
  countryCode,
  query,
  locations = [],
  limit = 20,
  fetchImpl = globalThis.fetch,
}) {
  const input = validateSearchInput({ countryCode, query, locations, limit });
  const url = new URL('https://jobicy.com/api/jobs');
  url.searchParams.set('count', '100');
  url.searchParams.set('geo', jobicyGeoByCountry[input.countryCode] || 'anywhere');
  url.searchParams.set('tag', input.query);

  await respectJobicyRateLimit();
  let response;
  try {
    response = await fetchImpl(url, {
      headers: { accept: 'application/json' },
      signal: AbortSignal.timeout(15_000),
    });
  } catch {
    throw new JobSearchError('The public Jobicy job feed could not be reached.');
  }
  if (response.status === 429) {
    throw new JobSearchError(
      'Jobicy is rate-limiting searches. Wait before trying again.',
      429,
      'job_search_rate_limited',
    );
  }
  if (!response.ok) {
    throw new JobSearchError(
      `Jobicy returned HTTP ${response.status} for this search.`,
      502,
    );
  }

  let result;
  try {
    result = await response.json();
  } catch {
    throw new JobSearchError('Jobicy returned an unreadable response.');
  }
  if (result?.success === false || !Array.isArray(result?.jobs)) {
    throw new JobSearchError('Jobicy returned an invalid job list.');
  }

  return result.jobs
    .map((job) => normalizeJobicyJob(job, input.countryCode))
    .filter((job) => job && job.title && job.postingUrl)
    .map((job) => ({ job, relevance: titleRelevance(job.title, input.query) }))
    .filter(({ relevance }) => relevance > 0)
    .sort((left, right) => right.relevance - left.relevance)
    .map(({ job }) => job)
    .slice(0, input.limit);
}

export async function searchJobListings(options) {
  const { env = process.env } = options;
  if (env.ADZUNA_APP_ID && env.ADZUNA_APP_KEY) {
    return {
      provider: 'Adzuna',
      jobs: await searchAdzunaJobs({ ...options, env }),
    };
  }
  return {
    provider: 'Jobicy',
    jobs: await searchJobicyJobs(options),
  };
}
