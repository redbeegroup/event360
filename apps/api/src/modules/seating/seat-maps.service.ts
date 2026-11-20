import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, SeatMap } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { expandSeats, Layout, validateLayout } from './layout';

export interface MapInput {
  venueName?: string;
  venueNameMy?: string;
  city?: string;
  address?: string;
  latitude?: number;
  longitude?: number;
  mapUrl?: string;
  isActive?: boolean;
}

@Injectable()
export class SeatMapsService {
  constructor(private readonly prisma: PrismaService) {}

  private async map(id: string) {
    const m = await this.prisma.seatMap.findUnique({ where: { id } });
    if (!m) throw new NotFoundException('Seat map not found');
    return m;
  }

  async list() {
    const rows = await this.prisma.seatMap.findMany({
      orderBy: { venueName: 'asc' },
      include: { versions: { select: { version: true, publishedAt: true, seatCount: true }, orderBy: { version: 'desc' } } },
    });
    return rows.map(({ versions, ...m }) => ({
      ...m,
      latestVersion: versions[0]?.version ?? null,
      latestPublishedVersion: versions.find((v) => v.publishedAt)?.version ?? null,
      hasDraft: versions.some((v) => !v.publishedAt),
    }));
  }

  create(dto: MapInput & { venueName: string; city: string }) {
    return this.prisma.seatMap.create({ data: { venueName: dto.venueName, venueNameMy: dto.venueNameMy, city: dto.city, address: dto.address, latitude: dto.latitude, longitude: dto.longitude, mapUrl: dto.mapUrl } });
  }

  async update(id: string, dto: MapInput) {
    await this.map(id);
    const data: Prisma.SeatMapUpdateInput = { ...this.fields(dto), ...(dto.isActive !== undefined ? { isActive: dto.isActive } : {}) };
    return this.prisma.seatMap.update({ where: { id }, data });
  }

  private fields(d: MapInput): Prisma.SeatMapUpdateInput {
    const out: Prisma.SeatMapUpdateInput = {};
    if (d.venueName !== undefined) out.venueName = d.venueName;
    if (d.venueNameMy !== undefined) out.venueNameMy = d.venueNameMy;
    if (d.city !== undefined) out.city = d.city;
    if (d.address !== undefined) out.address = d.address;
    if (d.latitude !== undefined) out.latitude = d.latitude;
    if (d.longitude !== undefined) out.longitude = d.longitude;
    if (d.mapUrl !== undefined) out.mapUrl = d.mapUrl;
    return out;
  }

  async get(id: string) {
    const m = await this.prisma.seatMap.findUnique({
      where: { id },
      include: { versions: { select: { id: true, version: true, seatCount: true, publishedAt: true, createdAt: true, createdById: true }, orderBy: { version: 'desc' } } },
    });
    if (!m) throw new NotFoundException('Seat map not found');
    return m;
  }

  async version(id: string, version: number) {
    const v = await this.prisma.seatMapVersion.findUnique({ where: { seatMapId_version: { seatMapId: id, version } } });
    if (!v) throw new NotFoundException('Version not found');
    return v;
  }

  /** Creates the single unpublished version (max+1), or replaces its layout if one exists. */
  async saveDraft(id: string, layoutInput: unknown, actorId: string) {
    const r = validateLayout(layoutInput);
    if (!r.ok) throw new BadRequestException({ message: 'Invalid layout', problems: r.problems });
    await this.map(id);
    const layout = r.layout as unknown as Prisma.InputJsonValue;
    const seatCount = expandSeats(r.layout).length;
    try {
      return await this.prisma.$transaction(async (tx) => {
        const draft = await tx.seatMapVersion.findFirst({ where: { seatMapId: id, publishedAt: null } });
        return this.writeDraft(tx, id, draft?.id ?? null, layout, seatCount, actorId);
      });
    } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') throw new ConflictException('Another draft was saved at the same time; try again');
      throw e;
    }
  }

  /**
   * Replaces the layout of draft `draftId`, guarded by publishedAt = null so a version published in the
   * meantime is never modified. If the draft is gone or was just published, a new draft (max+1) is created.
   * Public only so the race can be tested.
   */
  async writeDraft(tx: Prisma.TransactionClient, mapId: string, draftId: string | null, layout: Prisma.InputJsonValue, seatCount: number, actorId: string) {
    if (draftId) {
      const done = await tx.seatMapVersion.updateMany({ where: { id: draftId, publishedAt: null }, data: { layout, seatCount } });
      if (done.count === 1) return tx.seatMapVersion.findUniqueOrThrow({ where: { id: draftId } });
    }
    const max = await tx.seatMapVersion.aggregate({ where: { seatMapId: mapId }, _max: { version: true } });
    return tx.seatMapVersion.create({ data: { seatMapId: mapId, version: (max._max.version ?? 0) + 1, layout, seatCount, createdById: actorId } });
  }

  async publish(id: string, actorId: string) {
    await this.map(id);
    return this.prisma.$transaction(async (tx) => {
      const draft = await tx.seatMapVersion.findFirst({ where: { seatMapId: id, publishedAt: null } });
      if (!draft) throw new ConflictException('No draft to publish');
      const v = validateLayout(draft.layout);
      if (!v.ok) throw new BadRequestException({ message: 'Invalid layout', problems: v.problems });
      const seatCount = expandSeats(v.layout).length;
      const done = await tx.seatMapVersion.updateMany({ where: { id: draft.id, publishedAt: null }, data: { publishedAt: new Date(), seatCount } });
      if (done.count !== 1) throw new ConflictException('No draft to publish');
      await tx.auditLog.create({ data: { actorId, action: 'seatmap.publish', entityType: 'seat_map', entityId: id, data: { version: draft.version, seatCount } } });
      return tx.seatMapVersion.findUniqueOrThrow({ where: { id: draft.id } });
    });
  }

  /** Active maps that have at least one published version, for organizers. */
  async listPublished() {
    const rows = await this.prisma.seatMap.findMany({
      where: { isActive: true, versions: { some: { publishedAt: { not: null } } } },
      orderBy: { venueName: 'asc' },
      include: { versions: { where: { publishedAt: { not: null } }, orderBy: { version: 'desc' }, take: 1, select: { id: true, version: true, seatCount: true } } },
    });
    return rows.map((m) => ({
      id: m.id,
      venueName: m.venueName,
      venueNameMy: m.venueNameMy,
      city: m.city,
      address: m.address,
      latitude: m.latitude,
      longitude: m.longitude,
      mapUrl: m.mapUrl,
      latestVersionId: m.versions[0].id,
      latestVersion: m.versions[0].version,
      seatCount: m.versions[0].seatCount,
    }));
  }

  async publishedVersion(versionId: string): Promise<{ id: string; layout: Layout; seatMap: SeatMap }> {
    const v = await this.prisma.seatMapVersion.findUnique({ where: { id: versionId }, include: { seatMap: true } });
    if (!v || !v.publishedAt) throw new NotFoundException('Published seat map version not found');
    return { id: v.id, layout: v.layout as unknown as Layout, seatMap: v.seatMap };
  }
}
