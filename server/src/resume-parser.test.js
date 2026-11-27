import test from 'node:test';
import assert from 'node:assert/strict';
import PDFDocument from 'pdfkit';
import { Document, Packer, Paragraph } from 'docx';
import { extractResumeText } from './resume-parser.js';

async function createPdf(text) {
  return new Promise((resolve, reject) => {
    const pdf = new PDFDocument();
    const chunks = [];
    pdf.on('data', (chunk) => chunks.push(chunk));
    pdf.on('end', () => resolve(Buffer.concat(chunks)));
    pdf.on('error', reject);
    pdf.text(text);
    pdf.end();
  });
}

test('extracts readable text from PDF and DOCX resumes', async () => {
  const pdf = await createPdf('Alex Morgan\nSoftware Engineer');
  const docx = await Packer.toBuffer(
    new Document({
      sections: [{ children: [new Paragraph('Alex Morgan Product Designer')] }],
    }),
  );
  const pdfText = await extractResumeText(pdf, 'application/pdf');
  const docxText = await extractResumeText(
    docx,
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  );

  assert.match(pdfText, /Alex Morgan/);
  assert.match(docxText, /Alex Morgan Product Designer/);
});

test('rejects unsupported resume formats explicitly', async () => {
  await assert.rejects(
    extractResumeText(Buffer.from('resume'), 'text/plain'),
    { status: 415 },
  );
});
