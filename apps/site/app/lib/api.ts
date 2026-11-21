import 'server-only';
import { API_URL } from './config';

export interface TicketType {
  id: string;
  name: string;
  nameMy: string | null;
  priceMmk: number;
  remaining: number;
}

export interface EventCard {
  id: string;
  slug: string;
  status: string;
  title: string;
  titleMy: string | null;
  summary: string | null;
  summaryMy: string | null;
  coverImageUrl: string | null;
  format: 'IN_PERSON' | 'ONLINE' | 'HYBRID' | string;
  isFree: boolean;
  minPriceMmk: number | null;
  startsAt: string;
  endsAt: string;
  category: { id: string; slug: string; nameEn: string; nameMy: string | null };
  venue: { name: string; nameMy: string | null; address: string | null; city: string; mapUrl?: string | null; directions?: string | null; directionsMy?: string | null; latitude?: number | null; longitude?: number | null } | null;
  organization: { id: string; name: string; slug: string; kycStatus: string; logoUrl?: string | null };
  ticketTypes: TicketType[];
  soldOut: boolean;
}

export interface SeatsType {
  id: string;
  name: string;
  nameMy: string | null;
  priceMmk: number;
  color: string;
}
/** GET /v1/events/:id/seats (seated events only). */
export interface PublicSeats {
  versionId: string;
  layout: import('./seat-layout').Layout;
  types: SeatsType[];
  /** One char per seat in expandSeats() order: 0-9a-zA-Z index into `types`, '-' for none. */
  seatTypes: string;
  status: string;
}

export interface EventDetail extends EventCard {
  /** Present when the event has a seat map. */
  seating?: { seatMapVersionId: string; venueName: string | null } | null;
  description: string | null;
  descriptionMy: string | null;
  ageMin?: number | null;
  dressCode?: string | null;
  dressCodeMy?: string | null;
  languages?: string | null;
  languagesMy?: string | null;
  parking?: string | null;
  parkingMy?: string | null;
  accessibility?: string | null;
  accessibilityMy?: string | null;
  whatToBring?: string | null;
  whatToBringMy?: string | null;
  refundPolicy?: string | null;
  refundPolicyMy?: string | null;
  sessions: { id: string; title: string; titleMy: string | null; location: string | null; startsAt: string; endsAt: string }[];
  performers: { id: string; name: string; nameMy: string | null; role: string | null; roleMy: string | null; bio: string | null; bioMy: string | null; photoUrl: string | null }[];
  media: { id: string; url: string; caption: string | null; captionMy: string | null }[];
  faqs: { id: string; question: string; questionMy: string | null; answer: string; answerMy: string | null }[];
}

export interface Category {
  id: string;
  slug: string;
  nameEn: string;
  nameMy: string | null;
  children: { id: string; slug: string; nameEn: string; nameMy: string | null }[];
}

export interface Organizer {
  name: string;
  slug: string;
  description: string | null;
  descriptionMy: string | null;
  website: string | null;
  facebookUrl: string | null;
  logoUrl: string | null;
  verified: boolean;
  events: EventCard[];
}

export interface EventPage {
  items: EventCard[];
  page: number;
  limit: number;
  total: number;
}

/** Public API GET, cached for a minute (pages render on request; nothing is fetched at build time). */
async function get<T>(path: string, revalidate = 60): Promise<T | null> {
  try {
    const res = await fetch(`${API_URL}/v1${path}`, { next: { revalidate } });
    if (res.status === 404) return null;
    if (!res.ok) throw new Error(`API ${res.status} for ${path}`);
    return (await res.json()) as T;
  } catch (e) {
    console.error(`site: ${(e as Error).message}`);
    throw e;
  }
}

export const getEvents = (q: { q?: string; category?: string; city?: string; free?: boolean; page?: number; limit?: number } = {}) => {
  const p = new URLSearchParams();
  if (q.q) p.set('q', q.q);
  if (q.category) p.set('category', q.category);
  if (q.city) p.set('city', q.city);
  if (q.free) p.set('free', 'true');
  p.set('page', String(q.page ?? 1));
  p.set('limit', String(q.limit ?? 24));
  return get<EventPage>(`/events?${p}`).then((r) => r ?? { items: [], page: 1, limit: 24, total: 0 });
};
export const getEvent = (slug: string) => get<EventDetail>(`/events/${encodeURIComponent(slug)}`);
export const getCategories = () => get<Category[]>('/categories', 600).then((r) => r ?? []);
export const getOrganizer = (slug: string) => get<Organizer>(`/organizers/${encodeURIComponent(slug)}`);

/** Seat map for a seated event. Null when the event is not seated or the endpoint fails: the page then shows nothing. */
export const getSeats = (slug: string) => get<PublicSeats>(`/events/${encodeURIComponent(slug)}/seats`, 30).catch(() => null);
