import test from 'node:test';
import assert from 'node:assert/strict';
import {
  JobSearchError,
  searchAdzunaJobs,
  searchJobListings,
} from './job-search.js';
import { rankJobsByKeywordCoverage } from './job-match.js';

test('queries Adzuna per requested location and normalizes safe public listings', async () => {
  const requests = [];
  const jobs = await searchAdzunaJobs({
    env: { ADZUNA_APP_ID: 'test-id', ADZUNA_APP_KEY: 'test-key' },
    countryCode: 'in',
    query: 'product designer',
    locations: ['Chennai', 'Bengaluru'],
    limit: 20,
    fetchImpl: async (url) => {
      requests.push(new URL(url));
      const location = new URL(url).searchParams.get('where');
      return new Response(JSON.stringify({
        results: [{
          id: location,
          title: '<b>Product Designer</b>',
          company: { display_name: 'Example Studio' },
          location: { display_name: location },
          description: '<p>Design systems &amp; prototyping.</p>',
          redirect_url: 'http://www.adzuna.in/jobs/land/ad/example',
          salary_min: 800000,
          salary_max: 1200000,
          salary_currency: 'INR',
          salary_is_predicted: 1,
        }],
      }), { status: 200 });
    },
  });

  assert.equal(requests.length, 2);
  assert.equal(requests[0].searchParams.get('results_per_page'), '10');
  assert.equal(jobs.length, 2);
  assert.equal(jobs[0].title, 'Product Designer');
  assert.equal(jobs[0].description, 'Design systems & prototyping.');
  assert.equal(jobs[0].postingUrl, 'https://www.adzuna.in/jobs/land/ad/example');
  assert.equal(jobs[0].salaryIsPredicted, true);
  assert.equal(jobs[0].source, 'Adzuna');
});

test('fails explicitly when Adzuna credentials are not configured', async () => {
  await assert.rejects(
    searchAdzunaJobs({
      env: {},
      countryCode: 'in',
      query: 'designer',
    }),
    (error) =>
      error instanceof JobSearchError &&
      error.status === 503 &&
      error.code === 'job_search_not_configured',
  );
});

test('preserves long Adzuna descriptions for full preview in the app', async () => {
  const description = 'A'.repeat(8000);
  const jobs = await searchAdzunaJobs({
    env: { ADZUNA_APP_ID: 'test-id', ADZUNA_APP_KEY: 'test-key' },
    countryCode: 'in',
    query: 'designer',
    fetchImpl: async () => new Response(JSON.stringify({
      results: [{
        id: 'long-description',
        title: 'Designer',
        redirect_url: 'https://example.com/jobs/1',
        description,
      }],
    })),
  });

  assert.equal(jobs[0].description.length, 8000);
});

test('uses public Jobicy listings when Adzuna credentials are unavailable', async () => {
  let requestUrl;
  const result = await searchJobListings({
    env: {},
    countryCode: 'in',
    query: 'software engineer',
    locations: ['Bengaluru'],
    limit: 20,
    fetchImpl: async (url) => {
      requestUrl = new URL(url);
      return new Response(JSON.stringify({
        success: true,
        jobs: [{
          id: 122,
          url: 'https://jobicy.com/jobs/122-accountant',
          jobTitle: 'Senior Accountant',
          companyName: 'Unrelated Inc',
          jobGeo: 'APAC',
          jobDescription: 'Accounting and finance role.',
        }, {
          id: 123,
          url: 'https://jobicy.com/jobs/123-example-role',
          jobTitle: '<b>Software Engineer</b>',
          companyName: 'Example Company',
          jobGeo: 'APAC',
          jobDescription: '<p>Build reliable services &amp; APIs.</p>',
          jobType: ['Full-Time'],
          pubDate: '2026-11-25T10:00:00+00:00',
        }],
      }));
    },
  });

  assert.equal(result.provider, 'Jobicy');
  assert.equal(requestUrl.pathname, '/api/jobs');
  assert.equal(requestUrl.searchParams.get('count'), '100');
  assert.equal(requestUrl.searchParams.get('geo'), 'apac');
  assert.equal(requestUrl.searchParams.get('tag'), 'software engineer');
  assert.equal(result.jobs.length, 1);
  assert.equal(result.jobs[0].id, 'jobicy-123');
  assert.equal(result.jobs[0].title, 'Software Engineer');
  assert.equal(result.jobs[0].description, 'Build reliable services & APIs.');
  assert.equal(result.jobs[0].postingUrl, 'https://jobicy.com/jobs/123-example-role');
  assert.equal(result.jobs[0].source, 'Jobicy');
  assert.equal(result.jobs[0].salaryMin, null);
});

test('rejects invalid countries, result limits, and oversized location lists', async () => {
  const options = {
    env: { ADZUNA_APP_ID: 'test-id', ADZUNA_APP_KEY: 'test-key' },
    query: 'designer',
    fetchImpl: async () => new Response(JSON.stringify({ results: [] })),
  };

  for (const input of [
    { countryCode: 'india' },
    { countryCode: 'in', limit: 21 },
    { countryCode: 'in', locations: ['a', 'b', 'c', 'd', 'e', 'f'] },
  ]) {
    await assert.rejects(
      searchAdzunaJobs({ ...options, ...input }),
      JobSearchError,
    );
  }
});

test('ranks jobs locally from resume keyword evidence without an AI provider', () => {
  const ranked = rankJobsByKeywordCoverage([
    {
      id: 'accounting',
      title: 'Accountant',
      description: 'Prepare financial reports and tax statements.',
    },
    {
      id: 'flutter',
      title: 'Flutter Engineer',
      description: 'Build mobile apps with Dart and Flutter.',
    },
  ], {
    skills: ['Dart', 'Flutter'],
    experiences: [{
      title: 'Mobile Engineer',
      description: 'Built Android apps.',
    }],
    education: [],
  });

  assert.equal(ranked[0].id, 'flutter');
  assert.ok(ranked[0].fitScore > ranked[1].fitScore);
  assert.ok(ranked[0].reasons.some((reason) => reason.includes('dart')));
});
