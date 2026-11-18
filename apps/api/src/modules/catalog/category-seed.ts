/**
 * Default two-level category tree (ADR-0001). Admins can edit these later via the portal.
 * Myanmar names are a first draft — to be reviewed by a native speaker; admins can edit them later.
 */
export interface CategorySeed {
  slug: string;
  nameEn: string;
  nameMy: string;
  iconKey: string;
  children: { slug: string; nameEn: string; nameMy: string }[];
}

export const CATEGORY_SEED: CategorySeed[] = [
  {
    slug: 'lifestyle-social',
    nameEn: 'Lifestyle & Social',
    nameMy: 'လူနေမှုပုံစံနှင့် လူမှုရေး',
    iconKey: 'sparkles',
    children: [
      { slug: 'food-beverage-fair', nameEn: 'Food & Beverage Fair', nameMy: 'အစားအသောက်ပွဲ' },
      { slug: 'fashion-shows', nameEn: 'Fashion Shows', nameMy: 'ဖက်ရှင်ရှိုး' },
      { slug: 'art-exhibitions-galleries', nameEn: 'Art Exhibitions & Galleries', nameMy: 'အနုပညာပြပွဲများ' },
      { slug: 'meet-greet', nameEn: 'Meet & Greet Sessions', nameMy: 'တွေ့ဆုံပွဲများ' },
    ],
  },
  {
    slug: 'entertainment-culture',
    nameEn: 'Entertainment & Culture',
    nameMy: 'ဖျော်ဖြေရေးနှင့် ယဉ်ကျေးမှု',
    iconKey: 'music',
    children: [
      { slug: 'concerts-music-festivals', nameEn: 'Concerts & Music Festivals', nameMy: 'ဂီတဖျော်ဖြေပွဲများ' },
      { slug: 'musicals', nameEn: 'Musicals', nameMy: 'ဂီတပြဇာတ်များ' },
      { slug: 'cultural-festivals', nameEn: 'Cultural Festivals', nameMy: 'ယဉ်ကျေးမှုပွဲတော်များ' },
    ],
  },
  {
    slug: 'conference',
    nameEn: 'Conference',
    nameMy: 'ညီလာခံ',
    iconKey: 'presentation',
    children: [
      { slug: 'seminars', nameEn: 'Seminars', nameMy: 'ဆွေးနွေးပွဲများ' },
      { slug: 'conferences', nameEn: 'Conferences', nameMy: 'ညီလာခံများ' },
      { slug: 'summits', nameEn: 'Summits', nameMy: 'ထိပ်သီးအစည်းအဝေးများ' },
    ],
  },
  {
    slug: 'education-business',
    nameEn: 'Education & Business',
    nameMy: 'ပညာရေးနှင့် စီးပွားရေး',
    iconKey: 'briefcase',
    children: [
      { slug: 'workshops-training', nameEn: 'Workshops & Training', nameMy: 'အလုပ်ရုံဆွေးနွေးပွဲနှင့် သင်တန်းများ' },
      { slug: 'networking-events', nameEn: 'Networking Events', nameMy: 'အသိအကျွမ်းတိုးချဲ့ပွဲများ' },
    ],
  },
];
