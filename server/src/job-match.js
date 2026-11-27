import { scoreKeywordCoverage } from './ats.js';

export function rankJobsByKeywordCoverage(jobs, profile) {
  const resumeText = [
    ...(Array.isArray(profile.skills) ? profile.skills : []),
    ...(Array.isArray(profile.experiences)
      ? profile.experiences.flatMap((experience) => [
          experience.title,
          experience.description,
        ])
      : []),
    ...(Array.isArray(profile.education)
      ? profile.education.flatMap((education) => [
          education.degree,
          education.field,
        ])
      : []),
  ].filter(Boolean).join('\n');

  return jobs
    .map((job) => {
      const coverage = scoreKeywordCoverage(
        `${job.title}\n${job.description}`,
        resumeText,
      );
      return {
        ...job,
        fitScore: coverage.score ?? 0,
        reasons: coverage.matchedKeywords
          .slice(0, 3)
          .map((keyword) => `Resume includes ${keyword}`),
        gaps: coverage.missingKeywords
          .slice(0, 3)
          .map((keyword) => `No resume evidence for ${keyword}`),
      };
    })
    .sort((left, right) => right.fitScore - left.fitScore);
}
