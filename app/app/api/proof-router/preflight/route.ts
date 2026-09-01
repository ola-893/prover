import {
  PreflightInputError,
  runProofPreflight,
  validatePreflightRequest,
} from '@/lib/proof-preflight';

const MAX_BODY_BYTES = 16 * 1024;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'cache-control': 'private, no-store, max-age=0',
      'content-type': 'application/json; charset=utf-8',
      'x-content-type-options': 'nosniff',
    },
  });
}

async function readBoundedBody(request: Request): Promise<string> {
  const declaredLength = Number(request.headers.get('content-length'));
  if (Number.isFinite(declaredLength) && declaredLength > MAX_BODY_BYTES) {
    throw new PreflightInputError('Request body exceeds 16 KiB.');
  }
  const reader = request.body?.getReader();
  if (!reader) throw new PreflightInputError('Request body is required.');
  const decoder = new TextDecoder();
  let body = '';
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > MAX_BODY_BYTES) {
      await reader.cancel();
      throw new PreflightInputError('Request body exceeds 16 KiB.');
    }
    body += decoder.decode(value, { stream: true });
  }
  return body + decoder.decode();
}

export async function POST(request: Request): Promise<Response> {
  const contentType = request.headers.get('content-type') ?? '';
  if (
    contentType.split(';', 1)[0].trim().toLowerCase() !== 'application/json'
  ) {
    return json({ error: 'Content-Type must be application/json.' }, 415);
  }
  const origin = request.headers.get('origin');
  if (origin && origin !== new URL(request.url).origin) {
    return json(
      { error: 'Cross-origin preflight requests are not allowed.' },
      403,
    );
  }

  try {
    const text = await readBoundedBody(request);
    let payload: unknown;
    try {
      payload = JSON.parse(text);
    } catch {
      return json({ error: 'Request body must be valid JSON.' }, 400);
    }
    const preflightRequest = validatePreflightRequest(payload);
    return json(await runProofPreflight(preflightRequest, request.signal));
  } catch (error) {
    if (error instanceof PreflightInputError) {
      const status = error.message.includes('16 KiB') ? 413 : 400;
      return json({ error: error.message }, status);
    }
    return json({ error: 'Preflight could not be completed.' }, 500);
  }
}
