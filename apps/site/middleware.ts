import { NextRequest, NextResponse } from 'next/server';

/**
 * - www.event360.app → event360.app (one canonical host)
 * - English is served at the root (rewritten to /en internally); Myanmar lives under /my
 * - /en/... is redirected to the root form so each page has one English URL
 */
export function middleware(req: NextRequest) {
  const url = req.nextUrl;
  const host = req.headers.get('host') ?? '';
  if (host.startsWith('www.')) {
    const to = new URL(url.pathname + url.search, `https://${host.slice(4)}`);
    return NextResponse.redirect(to, 308);
  }
  const p = url.pathname;
  if (p === '/en' || p.startsWith('/en/')) {
    const u = url.clone();
    u.pathname = p.slice(3) || '/';
    return NextResponse.redirect(u, 308);
  }
  if (p === '/my' || p.startsWith('/my/')) return NextResponse.next();
  const u = url.clone();
  u.pathname = `/en${p === '/' ? '' : p}`;
  return NextResponse.rewrite(u);
}

export const config = {
  // Not for Next internals, files (favicon, robots.txt, sitemap.xml, images) or the health check
  matcher: ['/((?!_next/|healthz|.*\\..*).*)'],
};
