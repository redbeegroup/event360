/**
 * Server-side error reporting: unhandled errors while rendering pages or running server actions are sent
 * to the API's error tracker (Admin → Operations). Never blocks or breaks the response.
 */
export function register() {}

export async function onRequestError(
  err: unknown,
  request: { path: string; method: string },
  context: { routerKind: string; routePath: string; routeType: string },
) {
  const e = err as { message?: string; stack?: string; digest?: string };
  // Next.js uses thrown errors for redirect() and notFound(); those are not failures
  if (typeof e?.digest === 'string' && /^(NEXT_REDIRECT|NEXT_NOT_FOUND|NEXT_HTTP_ERROR_FALLBACK)/.test(e.digest)) return;
  const api = process.env.API_URL ?? 'http://localhost:3000';
  try {
    await fetch(`${api}/v1/telemetry/errors`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        source: 'portal',
        message: String(e?.message ?? err).slice(0, 1000),
        stack: e?.stack?.slice(0, 8000),
        path: `${request.method} ${context.routePath}`.slice(0, 300),
        release: process.env.APP_VERSION,
        context: { routeType: context.routeType, routerKind: context.routerKind },
      }),
      signal: AbortSignal.timeout(3000),
      cache: 'no-store',
    });
  } catch {
    // reporting must never fail the request
  }
}
