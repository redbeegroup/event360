import { Injectable } from '@nestjs/common';
import { MicroCache, publicCacheMs } from '../../common/micro-cache';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class CatalogService {
  constructor(private readonly prisma: PrismaService) {}

  // Categories change rarely; one read a minute per pod is plenty
  private readonly cache = new MicroCache<unknown>(publicCacheMs(60_000), 1);

  /** Active top-level categories with their active children, ordered for display. */
  categoryTree() {
    return this.cache.get('tree', () => this.loadTree()) as ReturnType<CatalogService['loadTree']>;
  }

  private loadTree() {
    return this.prisma.category.findMany({
      where: { parentId: null, isActive: true },
      orderBy: { sortOrder: 'asc' },
      select: {
        id: true,
        slug: true,
        nameEn: true,
        nameMy: true,
        iconKey: true,
        children: {
          where: { isActive: true },
          orderBy: { sortOrder: 'asc' },
          select: { id: true, slug: true, nameEn: true, nameMy: true },
        },
      },
    });
  }
}
