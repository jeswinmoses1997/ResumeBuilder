import mammoth from 'mammoth';
import { PDFParse } from 'pdf-parse';

export async function extractResumeText(buffer, mimeType) {
  if (mimeType === 'application/pdf') {
    const parser = new PDFParse({ data: buffer });
    try {
      return (await parser.getText()).text;
    } finally {
      await parser.destroy();
    }
  }
  if (
    mimeType ===
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
  ) {
    return (await mammoth.extractRawText({ buffer })).value;
  }
  const error = new Error('Upload a PDF or DOCX file.');
  error.status = 415;
  throw error;
}
