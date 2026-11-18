export const API_URL = process.env.API_URL ?? 'http://localhost:3000';

export interface Category {
  id: string;
  slug: string;
  nameEn: string;
  nameMy: string | null;
  children: { id: string; slug: string; nameEn: string }[];
}

export async function fetchCategories(): Promise<Category[]> {
  try {
    const res = await fetch(`${API_URL}/v1/categories`, { next: { revalidate: 60 } });
    return res.ok ? res.json() : [];
  } catch {
    return [];
  }
}
