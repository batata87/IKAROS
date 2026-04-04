import OpenAI from 'openai';

const SECRET_CONCEPT =
  process.env.IKAROS_SECRET || process.env.LOGIOS_SECRET || 'Eternity';

const corsJson = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

export const handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') {
    return { statusCode: 204, headers: corsJson, body: '' };
  }

  if (event.httpMethod !== 'POST') {
    return {
      statusCode: 405,
      headers: corsJson,
      body: JSON.stringify({ error: 'method not allowed' }),
    };
  }

  let word = '';
  try {
    const body = JSON.parse(event.body || '{}');
    word = typeof body.word === 'string' ? body.word.trim() : '';
  } catch {
    return {
      statusCode: 400,
      headers: corsJson,
      body: JSON.stringify({ error: 'invalid json' }),
    };
  }

  if (!word) {
    return {
      statusCode: 400,
      headers: corsJson,
      body: JSON.stringify({ error: 'word required' }),
    };
  }

  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    return {
      statusCode: 503,
      headers: corsJson,
      body: JSON.stringify({ error: 'OPENAI_API_KEY not configured' }),
    };
  }

  const openai = new OpenAI({ apiKey });

  try {
    const completion = await openai.chat.completions.create({
      model: process.env.OPENAI_MODEL || 'gpt-4o-mini',
      temperature: 0.2,
      max_tokens: 80,
      messages: [
        {
          role: 'system',
          content: `You compare a single user word/phrase to a secret target concept for a game called IKAROS.
The secret concept is: "${SECRET_CONCEPT}".
Respond with ONLY valid JSON: {"score": <integer 0-100>}
Rules:
- score is semantic similarity / conceptual overlap (not spelling).
- Identical or trivial synonym of the secret concept = 100.
- Unrelated = low single digits to ~15.
- Partially related themes scale between roughly 20-95.
No markdown, no explanation, JSON only.`,
        },
        {
          role: 'user',
          content: `User input: ${word.slice(0, 200)}`,
        },
      ],
    });

    const text = completion.choices[0]?.message?.content?.trim() || '';
    let score = 0;
    try {
      const parsed = JSON.parse(text.replace(/^```json\s*|\s*```$/g, ''));
      score = Math.round(Number(parsed.score));
    } catch {
      const m = text.match(/"score"\s*:\s*(\d+)/);
      if (m) score = Math.round(Number(m[1]));
    }
    if (Number.isNaN(score)) score = 0;
    score = Math.min(100, Math.max(0, score));

    return {
      statusCode: 200,
      headers: corsJson,
      body: JSON.stringify({ score }),
    };
  } catch (e) {
    console.error(e);
    return {
      statusCode: 500,
      headers: corsJson,
      body: JSON.stringify({ error: 'sync_failed' }),
    };
  }
};
