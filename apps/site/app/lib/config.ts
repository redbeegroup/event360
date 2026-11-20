/** Runtime settings (set per environment in the Kubernetes manifests). */
export const API_URL = process.env.API_URL ?? 'http://localhost:3000'; // in-cluster API, server-side only
export const SITE_URL = (process.env.SITE_URL ?? 'http://localhost:3002').replace(/\/$/, '');
export const APP_URL = (process.env.APP_URL ?? 'https://app.event360.app').replace(/\/$/, '');
export const PORTAL_URL = (process.env.PORTAL_URL ?? 'https://portal.event360.app').replace(/\/$/, '');
export const CONTACT_EMAIL = process.env.CONTACT_EMAIL ?? 'support@event360.app';
export const OPERATOR = process.env.SITE_OPERATOR ?? 'Event 360';
/** Dev and other non-production sites ask search engines not to index them. */
export const INDEXABLE = process.env.SITE_INDEXABLE === 'true';

/** Where "Get tickets" goes: the Event 360 web app (works on any phone; the Android app opens the same link later). */
export const ticketsUrl = (slug: string) => `${APP_URL}/#/event/${encodeURIComponent(slug)}`;
