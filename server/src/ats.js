const STOP_WORDS = new Set([
  'about', 'after', 'also', 'and', 'are', 'for', 'from', 'have', 'into',
  'job', 'our', 'role', 'that', 'the', 'their', 'this', 'with', 'you',
  'your', 'will', 'years', 'year', 'work', 'working', 'experience',
]);

function terms(value) {
  return new Set(
    (value.toLowerCase().match(/[a-z][a-z0-9+#.-]{1,}/g) || [])
      .map((term) => term.replace(/[.-]+$/, ''))
      .filter((term) => term.length > 1)
      .filter((term) => !STOP_WORDS.has(term) && !/^\d+$/.test(term)),
  );
}

export function scoreKeywordCoverage(jobDescription, resumeText) {
  if (!jobDescription.trim() || !resumeText.trim()) {
    return {
      score: null,
      matchedKeywords: [],
      missingKeywords: [],
      message: 'Add both a job description and resume content to calculate coverage.',
    };
  }

  const jobTerms = terms(jobDescription);
  const resumeTerms = terms(resumeText);
  if (!jobTerms.size) {
    return {
      score: null,
      matchedKeywords: [],
      missingKeywords: [],
      message: 'The job description has no scorable keywords.',
    };
  }
  const matchedKeywords = [...jobTerms].filter((term) => resumeTerms.has(term)).sort();
  const missingKeywords = [...jobTerms].filter((term) => !resumeTerms.has(term)).sort();
  const score = Math.round((matchedKeywords.length / jobTerms.size) * 100);

  return {
    score,
    matchedKeywords,
    missingKeywords,
    message:
      'Estimated keyword coverage only; this is not an ATS vendor score or a hiring prediction.',
  };
}
