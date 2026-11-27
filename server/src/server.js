import 'dotenv/config';
import { randomBytes } from 'node:crypto';
import cors from 'cors';
import express from 'express';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';
import multer from 'multer';
import { scoreKeywordCoverage } from './ats.js';
import { createDocumentArchive } from './documents.js';
import { createProviderRouter, ProviderError } from './provider-router.js';
import { extractResumeText } from './resume-parser.js';
import { JobSearchError, searchJobListings } from './job-search.js';
import { rankJobsByKeywordCoverage } from './job-match.js';
import { toPlainText } from './plain-text.js';

const app = express();
const providerRouter = createProviderRouter();
const linkedInStates = new Map();
const maxUploadBytes = (Number(process.env.MAX_UPLOAD_MB) || 10) * 1024 * 1024;
const allowedOrigins = (process.env.CORS_ORIGINS || '')
  .split(',')
  .map((origin) => origin.trim())
  .filter(Boolean);

app.disable('x-powered-by');
app.use(helmet());
app.use(cors({
  origin(origin, callback) {
    if (!origin || allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      const error = new Error('Origin is not allowed by CORS.');
      error.status = 403;
      callback(error);
    }
  },
}));
app.use(express.json({ limit: '1mb' }));
app.use(rateLimit({ windowMs: 60_000, limit: 30, standardHeaders: true }));

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: maxUploadBytes, files: 1 },
  fileFilter(_req, file, callback) {
    const allowed = new Set([
      'application/pdf',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    ]);
    if (!allowed.has(file.mimetype)) {
      const error = new Error('Upload a PDF or DOCX file.');
      error.status = 415;
      callback(error);
      return;
    }
    callback(null, true);
  },
});

function requireText(value, field, max = 30_000) {
  if (typeof value !== 'string' || value.length > max) {
    const error = new Error(`${field} must be a text value under ${max} characters.`);
    error.status = 400;
    throw error;
  }
  return value.trim();
}

app.get('/api/health', (_req, res) => {
  res.json({
    status: 'ok',
    configuredProviders: providerRouter.configuredProviders(),
    linkedInConfigured: Boolean(
      process.env.LINKEDIN_CLIENT_ID && process.env.LINKEDIN_CLIENT_SECRET,
    ),
  });
});

app.post('/api/linkedin/start', (_req, res) => {
  const { LINKEDIN_CLIENT_ID: clientId, LINKEDIN_REDIRECT_URI: redirectUri } =
    process.env;
  if (!clientId || !process.env.LINKEDIN_CLIENT_SECRET || !redirectUri) {
    return res.status(503).json({
      error: 'LinkedIn OAuth is not configured on the server.',
    });
  }
  for (const [pendingState, pending] of linkedInStates) {
    if (pending.expiresAt < Date.now()) linkedInStates.delete(pendingState);
  }
  const state = randomBytes(32).toString('base64url');
  linkedInStates.set(state, { expiresAt: Date.now() + 5 * 60_000 });
  const url = new URL('https://www.linkedin.com/oauth/v2/authorization');
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('client_id', clientId);
  url.searchParams.set('redirect_uri', redirectUri);
  url.searchParams.set('scope', 'openid profile email');
  url.searchParams.set('state', state);
  res.json({ state, authorizeUrl: url.toString() });
});

app.get('/api/linkedin/callback', async (req, res) => {
  const state = typeof req.query.state === 'string' ? req.query.state : '';
  const pending = linkedInStates.get(state);
  if (!pending || pending.expiresAt < Date.now()) {
    linkedInStates.delete(state);
    return res.status(400).send('This LinkedIn sign-in session expired. Return to the app and try again.');
  }
  if (typeof req.query.error === 'string') {
    pending.result = { error: 'LinkedIn sign-in was not completed.' };
    return res.type('html').send(
      '<!doctype html><title>Sign-in cancelled</title><p>You can close this tab and return to Resume Studio.</p>',
    );
  }
  if (pending.processing || typeof req.query.code !== 'string') {
    return res.status(400).send('This LinkedIn sign-in response is invalid.');
  }
  pending.processing = true;
  try {
    const tokenResponse = await fetch('https://www.linkedin.com/oauth/v2/accessToken', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'authorization_code',
        code: String(req.query.code || ''),
        redirect_uri: process.env.LINKEDIN_REDIRECT_URI,
        client_id: process.env.LINKEDIN_CLIENT_ID,
        client_secret: process.env.LINKEDIN_CLIENT_SECRET,
      }),
      signal: AbortSignal.timeout(15_000),
    });
    if (!tokenResponse.ok) throw new Error('LinkedIn token exchange failed.');
    const token = await tokenResponse.json();
    const profileResponse = await fetch('https://api.linkedin.com/v2/userinfo', {
      headers: { authorization: `Bearer ${token.access_token}` },
      signal: AbortSignal.timeout(15_000),
    });
    if (!profileResponse.ok) throw new Error('LinkedIn profile request failed.');
    const profile = await profileResponse.json();
    pending.result = {
      name: profile.name || '',
      email: profile.email || '',
      linkedinUrl: '',
      notice:
        'LinkedIn sign-in provides only fields allowed by your app access. Skills and work history may not be available; add them manually or import a profile document.',
    };
  } catch {
    pending.result = { error: 'LinkedIn sign-in could not retrieve an approved profile.' };
  } finally {
    pending.processing = false;
  }
  res.type('html').send(
    '<!doctype html><title>Return to Resume Studio</title><p>Sign-in finished. You can close this tab and return to Resume Studio.</p>',
  );
});

app.get('/api/linkedin/result/:state', (req, res) => {
  const pending = linkedInStates.get(req.params.state);
  if (!pending || pending.expiresAt < Date.now()) {
    linkedInStates.delete(req.params.state);
    return res.status(404).json({ error: 'This LinkedIn sign-in session expired.' });
  }
  if (!pending.result) return res.status(202).json({ status: 'pending' });
  linkedInStates.delete(req.params.state);
  if (pending.result.error) {
    return res.status(422).json({ error: pending.result.error });
  }
  res.set('cache-control', 'no-store').json(pending.result);
});

app.post('/api/ai/work-description', async (req, res, next) => {
  try {
    const title = requireText(req.body?.jobTitle, 'jobTitle', 200);
    if (!title) {
      return res.status(400).json({ error: 'Job title is required.' });
    }
    const result = await providerRouter.generate('work_experience', {
      jobTitle: title,
      company: requireText(req.body?.company || '', 'company', 200),
      location: requireText(req.body?.location || '', 'location', 200),
      verifiedDetails: requireText(req.body?.verifiedDetails || '', 'verifiedDetails', 5000),
      instruction:
        'Suggest role context as unverified options. Do not state that the user performed any task without confirmation. Return JSON: { "draft": string, "questions": string[], "unverifiedSuggestions": string[] }.',
    });
    res.json(result);
  } catch (error) {
    next(error);
  }
});

app.post('/api/ai/project-description', async (req, res, next) => {
  try {
    const idea = requireText(req.body?.idea, 'idea', 5000);
    if (!idea) return res.status(400).json({ error: 'Project idea is required.' });
    const result = await providerRouter.generate('project', {
      idea,
      verifiedDetails: requireText(req.body?.verifiedDetails || '', 'verifiedDetails', 5000),
      instruction:
        'Develop the supplied project idea into a professional draft without asserting unprovided implementation details. Return JSON: { "draft": string, "questions": string[], "unverifiedSuggestions": string[] }.',
    });
    res.json(result);
  } catch (error) {
    next(error);
  }
});

app.post('/api/ai/tailor', async (req, res, next) => {
  try {
    const profile = req.body?.profile;
    const jobDescription = requireText(
      req.body?.jobDescription || '',
      'jobDescription',
      20_000,
    );
    if (!profile || typeof profile !== 'object' || Array.isArray(profile)) {
      return res.status(400).json({ error: 'A profile object is required.' });
    }
    if (!jobDescription) {
      return res.status(400).json({ error: 'Job description is required.' });
    }
    const result = await providerRouter.generate('tailor', {
      profile,
      jobDescription,
      instruction:
        'Compare the user-provided resume facts with the job description. Return JSON: {"matchedSkills": string[], "suggestedSkills": string[], "experienceDrafts": [{"experienceIndex": number, "revisedDescription": string, "questions": string[]}], "recommendations": string[], "questions": string[]}. matchedSkills must already be in the supplied skills list. suggestedSkills are terms from the job description not evidenced in the profile; they are suggestions only and must never be added as user skills without explicit confirmation. For each experience rewrite, return its exact supplied experienceIndex and rewrite only from facts in that experience. If there are no supported changes, return an empty revisedDescription and ask questions instead. Never infer or invent.',
    });
    const output = result.output;
    if (
      !Array.isArray(output.matchedSkills) ||
      !Array.isArray(output.suggestedSkills) ||
      !Array.isArray(output.experienceDrafts) ||
      !Array.isArray(output.recommendations) ||
      !Array.isArray(output.questions)
    ) {
      return res.status(502).json({ error: 'AI response did not contain a valid tailoring review.' });
    }
    res.json(result);
  } catch (error) {
    next(error);
  }
});

app.post('/api/jobs/search', async (req, res, next) => {
  try {
    const query = requireText(req.body?.query || '', 'query', 200);
    const countryCode = requireText(
      req.body?.countryCode || 'in',
      'countryCode',
      2,
    ).toLowerCase();
    const profile = req.body?.profile;
    const locations = req.body?.locations ?? [];
    if (!profile || typeof profile !== 'object' || Array.isArray(profile)) {
      return res.status(400).json({ error: 'A resume profile is required for job matching.' });
    }
    if (!Array.isArray(locations)) {
      return res.status(400).json({ error: 'Locations must be provided as a list.' });
    }
    const { provider: listingProvider, jobs } = await searchJobListings({
      countryCode,
      query,
      locations,
      limit: req.body?.limit ?? 20,
    });
    if (!jobs.length) {
      return res.json({
        listingProvider,
        provider: null,
        matchMethod: 'none',
        jobs: [],
      });
    }

    const safeProfile = {
      skills: Array.isArray(profile.skills)
        ? profile.skills.filter((skill) => typeof skill === 'string').slice(0, 100)
        : [],
      experiences: Array.isArray(profile.experiences)
        ? profile.experiences
            .filter((entry) => entry && typeof entry === 'object')
            .slice(0, 15)
            .map((entry) => ({
              title: requireText(entry.title || '', 'experience title', 200),
              description: requireText(
                entry.description || '',
                'experience description',
                3000,
              ),
            }))
        : [],
      education: Array.isArray(profile.education)
        ? profile.education
            .filter((entry) => entry && typeof entry === 'object')
            .slice(0, 10)
            .map((entry) => ({
              degree: requireText(entry.degree || '', 'degree', 100),
              field: requireText(entry.fieldOfStudy || '', 'fieldOfStudy', 200),
            }))
        : [],
    };
    if (providerRouter.configuredProviders().length === 0) {
      return res.json({
        listingProvider,
        provider: null,
        matchMethod: 'local_keyword_coverage',
        jobs: rankJobsByKeywordCoverage(jobs, safeProfile),
      });
    }
    let matchResult;
    try {
      matchResult = await providerRouter.generate('job_match', {
        profile: safeProfile,
        jobs: jobs.map(({ id, title, company, location, description }) => ({
          id,
          title,
          company,
          location,
          description: description.slice(0, 1200),
        })),
        instruction:
          'Compare each job with only the supplied resume facts. Return JSON: {"matches":[{"jobId":string,"fitScore":number,"reasons":string[],"gaps":string[]}]}. Include exactly one match for every supplied job ID. fitScore is a rough 0-100 relevance estimate, never a hiring probability or guarantee. Give up to three short evidence-based reasons and gaps. Do not invent qualifications, infer protected characteristics, or use contact details.',
      });
    } catch (error) {
      if (!(error instanceof ProviderError)) throw error;
      return res.json({
        listingProvider,
        provider: null,
        matchMethod: 'local_keyword_coverage',
        jobs: rankJobsByKeywordCoverage(jobs, safeProfile),
      });
    }
    const rawMatches = matchResult.output?.matches;
    if (!Array.isArray(rawMatches) || rawMatches.length !== jobs.length) {
      return res.status(502).json({ error: 'AI returned an incomplete job-match review.' });
    }
    const matchesById = new Map();
    for (const match of rawMatches) {
      if (
        !match ||
        typeof match.jobId !== 'string' ||
        !jobs.some((job) => job.id === match.jobId) ||
        !Number.isFinite(match.fitScore) ||
        match.fitScore < 0 ||
        match.fitScore > 100 ||
        !Array.isArray(match.reasons) ||
        !Array.isArray(match.gaps) ||
        matchesById.has(match.jobId)
      ) {
        return res.status(502).json({ error: 'AI returned an invalid job-match review.' });
      }
      matchesById.set(match.jobId, {
        fitScore: Math.round(match.fitScore),
        reasons: match.reasons.filter((item) => typeof item === 'string').slice(0, 3),
        gaps: match.gaps.filter((item) => typeof item === 'string').slice(0, 3),
      });
    }
    const rankedJobs = jobs
      .map((job) => ({ ...job, ...matchesById.get(job.id) }))
      .sort((left, right) => right.fitScore - left.fitScore);
    res.json({
      listingProvider,
      provider: matchResult.provider,
      matchMethod: 'ai_relevance',
      jobs: rankedJobs,
    });
  } catch (error) {
    next(error);
  }
});

app.post('/api/ai/documents', async (req, res, next) => {
  try {
    const profile = req.body?.profile;
    const jobDescription = requireText(
      req.body?.jobDescription || '',
      'jobDescription',
      20_000,
    );
    if (!profile || typeof profile !== 'object' || Array.isArray(profile)) {
      return res.status(400).json({ error: 'A profile object is required.' });
    }
    const result = await providerRouter.generate('documents', {
      profile,
      jobDescription,
      instruction:
        'Create polished, ATS-readable resume, detailed CV, tailored cover letter, and an application/interview preparation kit using only supplied facts. Include the supplied email, phone, and LinkedIn in the resume, CV, and cover letter headers when present. Follow profile.tailoringInstructions only where supported by those facts. Proofread every document for spelling, grammar, punctuation, and natural sentence flow. Use concise, specific language and avoid generic filler. The application kit should contain draft answers for common application questions and likely interview questions with evidence-based talking points. Do not invent experience, salary expectations, work authorization, availability, metrics, or other personal facts; label unanswered items as questions for the applicant. Also return jobMatchScore as an integer from 0 to 100 estimating how well the supplied profile evidence matches the supplied job description, and up to three short jobMatchReasons grounded in the profile. This is a resume relevance estimate, not hiring probability and not an ATS score. Each document must be one plain-text string, never a nested object or array. Return JSON with string fields "resume", "cv", "coverLetter", and "applicationKit", plus jobMatchScore and jobMatchReasons. Do not claim human authorship, evade AI detectors, or guarantee a hiring outcome.',
    });
    const output = result.output;
    for (const key of ['resume', 'cv', 'coverLetter', 'applicationKit']) {
      output[key] = toPlainText(output[key]);
    }
    if (
      typeof output.resume !== 'string' ||
      typeof output.cv !== 'string' ||
      typeof output.coverLetter !== 'string' ||
      typeof output.applicationKit !== 'string' ||
      !output.resume.trim() ||
      !output.cv.trim() ||
      !output.coverLetter.trim() ||
      !output.applicationKit.trim() ||
      !Number.isInteger(output.jobMatchScore) ||
      output.jobMatchScore < 0 ||
      output.jobMatchScore > 100 ||
      !Array.isArray(output.jobMatchReasons)
    ) {
      return res.status(502).json({
        error: 'AI response did not contain the requested documents and a valid job match estimate.',
      });
    }
    output.jobMatchReasons = output.jobMatchReasons
      .filter((reason) => typeof reason === 'string')
      .slice(0, 3);
    res.json(result);
  } catch (error) {
    next(error);
  }
});

app.post('/api/resume/import', upload.single('resume'), async (req, res, next) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'Choose a PDF or DOCX resume.' });
    const text = await extractResumeText(req.file.buffer, req.file.mimetype);
    if (!text.trim()) {
      return res.status(422).json({ error: 'No readable text was found in that file.' });
    }
    const result = await providerRouter.generate('resume_extract', {
      resumeText: text.slice(0, 25_000),
      instruction:
        'Extract only explicit facts from this resume. Return JSON with keys name, email, phone, linkedin, skills (string array), experiences (array of objects with title, company, location, startDate, endDate, currentRole, description), education (array of objects with degree, institution, graduationYear, fieldOfStudy, project), and questions (array). Use empty strings/arrays for unknown values. Never infer facts.',
    });
    res.json({ fileName: req.file.originalname, ...result });
  } catch (error) {
    next(error);
  }
});

app.post('/api/ats/score', (req, res, next) => {
  try {
    const jobDescription = requireText(req.body?.jobDescription || '', 'jobDescription', 20_000);
    const resumeText = requireText(req.body?.resumeText || '', 'resumeText', 30_000);
    res.json(scoreKeywordCoverage(jobDescription, resumeText));
  } catch (error) {
    next(error);
  }
});

app.post('/api/documents/export', async (req, res, next) => {
  try {
    const name = requireText(req.body?.name || 'candidate', 'name', 200);
    const template = requireText(req.body?.template || 'modern', 'template', 30);
    const documents = req.body?.documents;
    if (!documents || typeof documents !== 'object' || Array.isArray(documents)) {
      return res.status(400).json({ error: 'Document content is required.' });
    }
    if (!['modern', 'classic', 'editorial'].includes(template)) {
      return res.status(400).json({ error: 'Choose a supported document style.' });
    }
    const zip = await createDocumentArchive({ name, documents, template });
    res.set({
      'content-type': 'application/zip',
      'content-disposition': 'attachment; filename="resume-package.zip"',
      'content-length': zip.length,
      'cache-control': 'no-store',
    });
    res.send(zip);
  } catch (error) {
    next(error);
  }
});

app.use((error, _req, res, _next) => {
  const status = error.status || (
    error instanceof multer.MulterError
      ? error.code === 'LIMIT_FILE_SIZE'
        ? 413
        : 400
      : 500
  );
  if (status >= 500) {
    console.error('Resume Studio request failed.', {
      name: error.name || 'Error',
      code: error.code,
    });
  }
  res.status(status).json({
    error:
      status < 500 ||       error instanceof ProviderError ||
      error instanceof JobSearchError
        ? error.message
        : 'The request could not be completed.',
    code: error.code,
  });
});

const port = Number(process.env.PORT) || 8787;
const host = process.env.HOST || '127.0.0.1';
app.listen(port, host, () => {
  console.log(`Resume Studio API listening on http://${host}:${port}`);
});
