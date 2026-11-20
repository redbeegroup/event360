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
  venue: {
    name: string;
    nameMy: string | null;
    address: string | null;
    city: string;
    mapUrl?: string | null;
    directions?: string | null;
    directionsMy?: string | null;
    latitude?: number | null;
    longitude?: number | null;
  } | null;
  organization: { id: string; name: string; slug: string; kycStatus: string; logoUrl?: string | null };
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
  terms?: string | null;
  termsMy?: string | null;
  refundPolicy?: string | null;
  refundPolicyMy?: string | null;
  transfersEnabled?: boolean;
  transferCutoffHours?: number;
  sessions?: { id: string; title: string; titleMy: string | null; description: string | null; descriptionMy: string | null; location: string | null; startsAt: string; endsAt: string }[];
  performers?: { id: string; name: string; nameMy: string | null; role: string | null; roleMy: string | null; bio: string | null; bioMy: string | null; photoKey: string | null; photoUrl: string | null }[];
  media?: { id: string; key: string; url: string; caption: string | null; captionMy: string | null }[];
  faqs?: { id: string; question: string; questionMy: string | null; answer: string; answerMy: string | null }[];
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
