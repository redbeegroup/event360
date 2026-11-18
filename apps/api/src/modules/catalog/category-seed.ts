/**
 * Default two-level category tree (ADR-0001). Admins can edit these later via the portal.
 * Myanmar names (name_my) are intentionally left for the localisation pass.
 */
export interface CategorySeed {
  slug: string;
  nameEn: string;
  iconKey: string;
  children: { slug: string; nameEn: string }[];
}

export const CATEGORY_SEED: CategorySeed[] = [
  {
    slug: 'lifestyle-social',
    nameEn: 'Lifestyle & Social',
    iconKey: 'sparkles',
    children: [
      { slug: 'food-beverage-fair', nameEn: 'Food & Beverage Fair' },
      { slug: 'fashion-shows', nameEn: 'Fashion Shows' },
      { slug: 'art-exhibitions-galleries', nameEn: 'Art Exhibitions & Galleries' },
      { slug: 'meet-greet', nameEn: 'Meet & Greet Sessions' },
    ],
  },
  {
    slug: 'entertainment-culture',
    nameEn: 'Entertainment & Culture',
    iconKey: 'music',
    children: [
      { slug: 'concerts-music-festivals', nameEn: 'Concerts & Music Festivals' },
      { slug: 'musicals', nameEn: 'Musicals' },
      { slug: 'cultural-festivals', nameEn: 'Cultural Festivals' },
    ],
  },
  {
    slug: 'conference',
    nameEn: 'Conference',
    iconKey: 'presentation',
    children: [
      { slug: 'seminars', nameEn: 'Seminars' },
      { slug: 'conferences', nameEn: 'Conferences' },
      { slug: 'summits', nameEn: 'Summits' },
    ],
  },
  {
    slug: 'education-business',
    nameEn: 'Education & Business',
    iconKey: 'briefcase',
    children: [
      { slug: 'workshops-training', nameEn: 'Workshops & Training' },
      { slug: 'networking-events', nameEn: 'Networking Events' },
    ],
  },
];
