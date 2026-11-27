import test from 'node:test';
import assert from 'node:assert/strict';
import { unzipSync } from 'fflate';
import { PDFParse } from 'pdf-parse';
import { createDocumentArchive } from './documents.js';

test('creates a ZIP with professionally formatted versions and the application kit', async () => {
  const archive = await createDocumentArchive({
    name: 'Alex Morgan',
    documents: {
      resume: '# Alex Morgan\n## EXPERIENCE\nDesigner',
      cv: '# Alex Morgan\n## EDUCATION\nBachelor of Design',
      coverLetter: '# Alex Morgan\nDear Hiring Team',
      applicationKit: '# Application answers\n## Interview preparation\nDiscuss your project.',
    },
    template: 'editorial',
  });
  const names = [
    'Alex-Morgan-resume.pdf',
    'Alex-Morgan-resume.docx',
    'Alex-Morgan-cv.pdf',
    'Alex-Morgan-cv.docx',
    'Alex-Morgan-cover-letter.pdf',
    'Alex-Morgan-cover-letter.docx',
    'Alex-Morgan-application-kit.pdf',
    'Alex-Morgan-application-kit.docx',
  ];

  assert.equal(archive.subarray(0, 2).toString(), 'PK');
  for (const name of names) {
    assert.ok(archive.includes(Buffer.from(name)), `Missing ${name}`);
  }
});

test('uses different visual styles when a different template is selected', async () => {
  const documents = {
    resume: '# Alex Morgan\n## EXPERIENCE\nDesigner',
    cv: '# Alex Morgan\n## EDUCATION\nBachelor of Design',
    coverLetter: '# Alex Morgan\nDear Hiring Team',
  };
  const modern = unzipSync(
    await createDocumentArchive({ name: 'Alex Morgan', documents, template: 'modern' }),
  );
  const classic = unzipSync(
    await createDocumentArchive({ name: 'Alex Morgan', documents, template: 'classic' }),
  );

  assert.notDeepEqual(
    modern['Alex-Morgan-resume.docx'],
    classic['Alex-Morgan-resume.docx'],
  );
  assert.notDeepEqual(
    modern['Alex-Morgan-resume.pdf'],
    classic['Alex-Morgan-resume.pdf'],
  );
});

test('does not print the document type above the PDF content', async () => {
  const archive = unzipSync(
    await createDocumentArchive({
      name: 'Alex Morgan',
      documents: {
        resume: '# Alex Morgan\nDesigner',
        cv: '# Alex Morgan\nDesigner',
        coverLetter: '# Alex Morgan\nDear Hiring Team',
      },
      template: 'modern',
    }),
  );
  const parser = new PDFParse({ data: archive['Alex-Morgan-resume.pdf'] });
  try {
    const { text } = await parser.getText();
    assert.ok(text.trimStart().startsWith('Alex Morgan'), text);
  } finally {
    await parser.destroy();
  }
});
