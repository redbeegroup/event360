import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import type { OrgRole } from '@prisma/client';
import { PrismaService } from '../modules/prisma/prisma.service';
import type { AuthUser } from './auth';

export const ORG_EDITORS: OrgRole[] = ['ORG_OWNER', 'ORG_MANAGER'];
export const ORG_VIEWERS: OrgRole[] = ['ORG_OWNER', 'ORG_MANAGER', 'ORG_FINANCE'];

/** Checks that a user may act on an organization (platform admins may act on any). */
@Injectable()
export class OrgAccessService {
  constructor(private readonly prisma: PrismaService) {}

  async assert(user: AuthUser, organizationId: string, allowed: OrgRole[] = ORG_EDITORS) {
    const org = await this.prisma.organization.findUnique({ where: { id: organizationId } });
    if (!org) throw new NotFoundException('Organization not found');
    if (user.roles?.includes('PLATFORM_ADMIN')) return org;
    const m = await this.prisma.organizationMember.findUnique({
      where: { organizationId_userId: { organizationId, userId: user.sub } },
    });
    if (!m || !allowed.includes(m.role)) throw new ForbiddenException('No access to this organization');
    return org;
  }
}
