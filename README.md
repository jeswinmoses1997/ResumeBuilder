# Resume Studio

A Flutter app with a local Node API for resume import, AI-assisted writing,
keyword coverage analysis, and PDF/DOCX exports.

## Requirements

- Flutter SDK and the platform toolchains for the targets you build.
- Node.js 20.16 or newer (or Node.js 22.3 or newer).
- At least one API key for OpenAI, Anthropic, Google Gemini, or Groq for AI
  features. Provider keys are optional until AI features are used.
- Adzuna API credentials for city-level job search. Register at
  [developer.adzuna.com](https://developer.adzuna.com/) and set
  `ADZUNA_APP_ID` and `ADZUNA_APP_KEY` in `server/.env`. Without them, the
  app falls back to [Jobicy's public remote-jobs feed](https://jobicy.com/api/job-board-api).
- LinkedIn app credentials and permission to use LinkedIn OpenID Connect for
  LinkedIn sign-in. LinkedIn profile fields beyond the approved scopes are not
  available to this app.

## Local setup

1. Generate Flutter platform runner folders if they are not present:

   ```sh
   flutter create .
   ```

2. Install API dependencies and configure server-only credentials:

   ```sh
   npm --prefix server install
   cp server/.env.example server/.env
   ```

   Edit `server/.env` locally. Add only the provider keys you have. Never paste
   keys into chat, commit them, or put them in Flutter `--dart-define` values.
   The API binds to `127.0.0.1` by default. Keep it private; do not expose this
   unauthenticated development API to the public internet. For LinkedIn, set
   the exact callback URI registered for your LinkedIn app in
   `LINKEDIN_REDIRECT_URI`; the callback must be reachable by LinkedIn.

3. Start the API and app in separate terminals:

   ```sh
   npm run dev:api
   flutter pub get
   flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8787
   ```

   For an Android emulator, use `http://10.0.2.2:8787`; for iOS simulator and
   desktop, `127.0.0.1` normally works. For a physical device, bind the API to
   a reachable LAN address and set `API_BASE_URL` to that address. Restrict
   access with your firewall and trusted CORS origins; use HTTPS outside local
   development.

4. Run API tests:

   ```sh
   npm run test:api
   ```

## What works

- AI provider routing among configured OpenAI, Anthropic, Gemini, and Groq
  accounts. Per-task preferences are set in `AI_ORDER_WRITING` and
  `AI_ORDER_STRUCTURED`; unavailable providers are skipped and provider errors
  are surfaced.
- PDF and DOCX text extraction followed by structured AI import.
- An import-review screen that lets you select, correct, merge, or replace
  extracted profile details, skills, work entries, and education before they
  enter the draft.
- A JD comparison step with user-approved skill suggestions and editable work
  rewrites. Missing skills are never added automatically.
- Resume, CV, cover-letter, and application/interview-kit generation with
  user review/editing and proofreading instructions before export. The ZIP
  contains a PDF and Word version of each document, with a choice of
  professional styles that cycles after a successful export. The review screen
  shows the final resume, a JD relevance estimate, and keyword coverage against
  the generated resume. Exports have no watermark.
- A locally persisted job tracker for company, role, location, salary range,
  job description, application link, and application status. Tracker entries
  are stored in the device's app preferences.
  The app can open an official HTTPS job page and prepare copyable draft
  answers, but the user reviews and submits each application. It does not
  create job-site accounts or submit applications autonomously.
- AI-ranked job search returning up to 20 listings with a resume relevance
  estimate. When configured, Adzuna searches one country and up to five cities;
  its advertiser link opens the full posting. Without Adzuna credentials, the
  app uses [Jobicy's free public feed](https://jobicy.com/api/job-board-api) of
  recent remote roles. Jobicy supports broad country/region filters rather
  than city filters; countries without a supported filter use its worldwide
  feed. It may return fewer than 20 results and links to the original Jobicy
  listing (where application options are shown). Salary estimates are labeled;
  when the listing has no salary, the app asks for the user's target range
  rather   than guessing. If no AI key is configured, job ranking uses local
  keyword coverage instead; resume text is not sent to an AI provider for that
  ranking, and document writing/tailoring still requires an AI provider.
- A transparent local ATS-style keyword coverage estimate. It is not a score
  from an ATS vendor or a hiring prediction.
- LinkedIn OpenID Connect sign-in can import fields returned by LinkedIn for
  the app's approved scopes. It does not scrape LinkedIn; skills and work
  history may require manual entry or a profile document.

The resume draft, including contact details, is saved automatically in the
device's app preferences without encryption; use "Clear saved draft" on the
first step to erase it. Job tracker entries are saved there too and can include
job descriptions and document package paths; remove app data to clear them. The development
API has no user accounts and is intended for private/local use, not public
deployment. A hosted release needs authentication, encrypted storage for any
retained data, HTTPS, and provider-specific privacy/retention review.
AI can help polish and proofread language, but it cannot guarantee error-free
writing, make AI authorship undetectable, or guarantee an interview. Verify
every factual claim and final application answer yourself.
Keep provider and Adzuna credentials in the ignored `server/.env` file; never
paste API keys into source files or commit them.

## License

Released under the [MIT License](LICENSE).
