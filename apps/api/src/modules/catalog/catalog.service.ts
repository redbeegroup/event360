import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class CatalogService {
  constructor(private readonly prisma: PrismaService) {}

  /** Active top-level categories with their active children, ordered for display. */
  categoryTree() {
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
