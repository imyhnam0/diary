import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { GoogleGenerativeAI } from '@google/generative-ai';

dotenv.config();

const app = express();
const port = Number(process.env.PORT || 8080);
const apiKey = (process.env.GEMINI_API_KEY || '').trim();
const modelName = (process.env.GEMINI_MODEL || 'gemini-2.5-flash-lite').trim();

app.use(cors());
app.use(express.json({ limit: '1mb' }));

function buildPrompt(language, targets) {
  return `
You are a diary sentence editor.

Rewrite only the "text" field of each object in the JSON array.

Rules:
- Keep the language of each target text exactly as the original text.
- Do not translate.
- If a target text is Korean, output Korean.
- If a target text is English, output English.
- If a target text is Japanese, output Japanese.
- If targets contain mixed languages, keep each item in its own original language.
- Preserve original meaning as much as possible.
- Preserve original tone, politeness level, and emotion.
- Correct typos, spacing, awkward grammar, and broken sentences naturally.
- If sentence is unclear, infer likely intent conservatively.
- Do not add new facts or events.
- Keep JSON structure unchanged.
- Keep each index unchanged.
- Modify only "text".
- Return only a valid JSON array.
- Do not include explanations or markdown.

Input:
${JSON.stringify(targets)}
`.trim();
}

function extractJsonArray(input) {
  const trimmed = String(input || '').trim();
  if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
    return trimmed;
  }

  const fencedMatch = trimmed.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
  const fenced = fencedMatch && fencedMatch[1] ? fencedMatch[1].trim() : null;
  if (fenced && fenced.startsWith('[') && fenced.endsWith(']')) {
    return fenced;
  }

  const start = trimmed.indexOf('[');
  const end = trimmed.lastIndexOf(']');
  if (start >= 0 && end > start) {
    return trimmed.slice(start, end + 1);
  }

  return null;
}

app.get('/health', (_, res) => {
  res.json({ ok: true });
});

app.post('/api/ai/rewrite', async (req, res) => {
  if (!apiKey) {
    res.status(500).json({ message: 'GEMINI_API_KEY is not configured.' });
    return;
  }

  const { language, targets } = req.body || {};
  if (!Array.isArray(targets) || targets.length === 0) {
    res.status(400).json({ message: '`targets` must be a non-empty array.' });
    return;
  }

  const sanitizedTargets = [];
  for (const item of targets) {
    if (!item || typeof item !== 'object') continue;
    const index = Number(item.index);
    const text = String(item.text || '').trim();
    if (!Number.isInteger(index) || index < 0 || !text) continue;
    sanitizedTargets.push({ index, text });
  }

  if (sanitizedTargets.length === 0) {
    res.status(400).json({ message: 'No valid targets to rewrite.' });
    return;
  }

  try {
    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({ model: modelName });
    const prompt = buildPrompt(language, sanitizedTargets);

    const result = await model.generateContent(prompt);
    const rawText = result?.response?.text()?.trim() || '';
    const jsonText = extractJsonArray(rawText);

    if (!jsonText) {
      res.status(502).json({ message: 'Could not parse AI result.' });
      return;
    }

    const parsed = JSON.parse(jsonText);
    if (!Array.isArray(parsed)) {
      res.status(502).json({ message: 'AI result format is invalid.' });
      return;
    }

    const items = [];
    for (const item of parsed) {
      if (!item || typeof item !== 'object') continue;
      const index = Number(item.index);
      const text = String(item.text || '').trim();
      if (!Number.isInteger(index) || index < 0 || !text) continue;
      items.push({ index, text });
    }

    res.json({ items });
  } catch (error) {
    console.error('AI rewrite error:', error);
    res.status(500).json({ message: 'Failed to rewrite with AI.' });
  }
});

app.listen(port, () => {
  console.log(`diary_back server listening on port ${port}`);
});
