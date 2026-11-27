import { zipSync } from 'fflate';
import PDFDocument from 'pdfkit';
import { Document, HeadingLevel, Packer, Paragraph, TextRun } from 'docx';

function cleanName(value) {
  return (value || 'candidate')
    .normalize('NFKD')
    .replace(/[^a-zA-Z0-9_-]+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, 60) || 'candidate';
}

function normalizeText(value) {
  return String(value || '').replace(/\r\n/g, '\n').trim();
}

const TEMPLATES = {
  modern: {
    accent: '236B62',
    ink: '172B3A',
    font: 'Arial',
    bodySize: 21,
    titleSize: 38,
    sectionSize: 24,
    margin: 58,
  },
  classic: {
    accent: '334155',
    ink: '1E293B',
    font: 'Georgia',
    bodySize: 22,
    titleSize: 40,
    sectionSize: 25,
    margin: 64,
  },
  editorial: {
    accent: '635B9A',
    ink: '29263D',
    font: 'Arial',
    bodySize: 21,
    titleSize: 42,
    sectionSize: 23,
    margin: 52,
  },
};

function documentTemplate(name) {
  return TEMPLATES[name] || TEMPLATES.modern;
}

// The built-in PDF fonts lack these characters and would print junk instead.
function pdfSafe(value) {
  return value
    .replace(/[‐-‒−]/g, '-')
    .replace(/[ -   ]/g, ' ')
    .replace(/[​-‍⁠﻿]/g, '')
    .replace(/₹\s?/g, 'INR ')
    .replace(/→/g, '->')
    .replace(/[▪●◦]/g, '•');
}

function contentLines(content) {
  return normalizeText(content)
    .split('\n')
    .map((text) => text.trim())
    .filter(Boolean);
}

function heading(line, index) {
  if (/^#\s+/.test(line) || index === 0) return 1;
  if (/^##\s+/.test(line)) return 2;
  return 0;
}

function withoutMarkdownHeading(line) {
  return line.replace(/^#{1,2}\s+/, '');
}

function toDocx(title, content, template) {
  const paragraphs = contentLines(content).map((text, index) => {
    const level = heading(text, index);
    if (level) {
      return new Paragraph({
        children: [
          new TextRun({
            text: withoutMarkdownHeading(text),
            bold: true,
            font: template.font,
            size: level === 1 ? template.titleSize : template.sectionSize,
            color: level === 1 ? template.ink : template.accent,
          }),
        ],
        heading: level === 1 ? HeadingLevel.HEADING_1 : HeadingLevel.HEADING_2,
        spacing: {
          before: level === 1 ? 200 : 150,
          after: level === 1 ? 120 : 90,
        },
      });
    }
    return new Paragraph({
      children: [
        new TextRun({
          text,
          font: template.font,
          size: template.bodySize,
          color: template.ink,
        }),
      ],
      spacing: { after: 110 },
    });
  });
  const document = new Document({
    title,
    sections: [{ properties: {}, children: paragraphs }],
  });
  return Packer.toBuffer(document);
}

function toPdf(title, content, template) {
  return new Promise((resolve, reject) => {
    const pdf = new PDFDocument({
      size: 'LETTER',
      margins: {
        top: 58,
        bottom: 58,
        left: template.margin,
        right: template.margin,
      },
      bufferPages: true,
      info: { Title: title },
    });
    const chunks = [];
    pdf.on('data', (chunk) => chunks.push(chunk));
    pdf.on('end', () => resolve(Buffer.concat(chunks)));
    pdf.on('error', reject);
    pdf
      .save()
      .rect(
        pdf.page.margins.left,
        pdf.page.margins.top - 14,
        pdf.page.width - pdf.page.margins.left - pdf.page.margins.right,
        3,
      )
      .fill(`#${template.accent}`)
      .restore();
    contentLines(pdfSafe(content)).forEach((line, index) => {
      const level = heading(line, index);
      if (level) {
        pdf.moveDown(level === 1 ? 0.35 : 0.2);
        pdf
          .font('Helvetica-Bold')
          .fontSize(level === 1 ? template.titleSize / 2 : template.sectionSize / 2)
          .fillColor(level === 1 ? `#${template.ink}` : `#${template.accent}`)
          .text(withoutMarkdownHeading(line), { lineGap: 2 });
        pdf.moveDown(0.2);
      } else {
        pdf
          .font(template.font === 'Georgia' ? 'Times-Roman' : 'Helvetica')
          .fontSize(template.bodySize / 2)
          .fillColor(`#${template.ink}`);
        pdf.text(line, { lineGap: template.font === 'Georgia' ? 4 : 3 });
        pdf.moveDown(0.25);
      }
    });
    const pages = pdf.bufferedPageRange();
    for (let index = 0; index < pages.count; index += 1) {
      pdf.switchToPage(pages.start + index);
      pdf
        .font('Helvetica')
        .fontSize(8)
        .fillColor('#71808C')
        .text(
          `${index + 1}`,
          0,
          pdf.page.height - pdf.page.margins.bottom / 2,
          { align: 'center', lineBreak: false },
        );
    }
    pdf.end();
  });
}

export async function createDocumentArchive({
  name,
  documents,
  template: templateName,
}) {
  const safeName = cleanName(name);
  const template = documentTemplate(templateName);
  const types = [
    ['resume', 'Resume'],
    ['cv', 'CV'],
    ['coverLetter', 'Cover Letter'],
    ['applicationKit', 'Application and Interview Kit'],
  ];
  const files = [];
  for (const [key, title] of types) {
    const content = normalizeText(documents?.[key]);
    if (!content && key === 'applicationKit') continue;
    if (!content) {
      throw new Error(`Missing ${title.toLowerCase()} content.`);
    }
    const basename = {
      coverLetter: 'cover-letter',
      applicationKit: 'application-kit',
    }[key] || key;
    files.push(
      {
        name: `${safeName}-${basename}.docx`,
        data: await toDocx(title, content, template),
      },
      {
        name: `${safeName}-${basename}.pdf`,
        data: await toPdf(title, content, template),
      },
    );
  }

  const entries = Object.fromEntries(
    files.map((file) => [file.name, file.data]),
  );
  return Buffer.from(zipSync(entries, { level: 6 }));
}
