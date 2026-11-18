export interface TicketTypeDto {
  id: string;
  name: string;
  nameMy: string | null;
  priceMmk: number;
  quota: number;
  remaining: number;
  sold?: number;
  maxPerOrder: number;
  deliveryMode: string;
}

export interface EventDto {
  id: string;
  slug: string;
  status: string;
  title: string;
  titleMy: string | null;
  summary: string | null;
  summaryMy: string | null;
  description?: string | null;
  descriptionMy?: string | null;
  rejectionReason?: string | null;
  coverImageKey: string | null;
  coverImageUrl: string | null;
  format: string;
  visibility: string;
  isFree: boolean;
  minPriceMmk: number | null;
  startsAt: string;
  endsAt: string;
  publishedAt: string | null;
  category: { id: string; slug: string; nameEn: string; nameMy: string | null };
  venue: { name: string; nameMy: string | null; address: string | null; city: string } | null;
  organization: { id: string; name: string; slug: string; kycStatus: string };
  ticketTypes: TicketTypeDto[];
  soldOut: boolean;
}

export interface CategoryDto {
  id: string;
  slug: string;
  nameEn: string;
  nameMy: string | null;
  children: { id: string; slug: string; nameEn: string; nameMy: string | null }[];
}
