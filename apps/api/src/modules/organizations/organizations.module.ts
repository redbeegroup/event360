import { Body, Controller, Get, Injectable, Module, NotFoundException, Param, ParseUUIDPipe, Patch, Post } from '@nestjs/common';
import { ApiProperty, ApiPropertyOptional, ApiTags } from '@nestjs/swagger';
import type { KycStatus, OrgRole } from '@prisma/client';
import { IsEmail, IsIn, IsOptional, IsString, Length, Matches, MaxLength } from 'class-validator';
import { Auth, AuthUser, CurrentUser } from '../../common/auth';
import { OrgAccessService } from '../../common/org-access.service';
import { AuthModule } from '../auth/auth.module';
import { AuthService } from '../auth/auth.service';
import { PrismaService } from '../prisma/prisma.service';

const INVITABLE_ROLES: OrgRole[] = ['ORG_OWNER', 'ORG_MANAGER', 'ORG_FINANCE'];

class CreateOrganizationDto {
  @ApiProperty() @IsString() @Length(2, 120) name: string;
  @ApiProperty({ example: 'yangon-live-events' })
  @Matches(/^[a-z0-9]+(?:-[a-z0-9]+)*$/, { message: 'slug: lowercase letters, digits and dashes' })
  @Length(2, 60)
  slug: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(2000) description?: string;
  @ApiProperty({ description: 'Email of the owner who receives the invite link' }) @IsEmail() ownerEmail: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(30) contactPhone?: string;
}

class SetKycDto {
  @ApiProperty({ enum: ['PENDING', 'APPROVED', 'REJECTED'] }) @IsIn(['PENDING', 'APPROVED', 'REJECTED']) status: KycStatus;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(1000) note?: string;
}

class InviteMemberDto {
  @ApiProperty() @IsEmail() email: string;
  @ApiProperty({ enum: INVITABLE_ROLES }) @IsIn(INVITABLE_ROLES) role: OrgRole;
}

@Injectable()
export class OrganizationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly auth: AuthService,
  ) {}

  async create(dto: CreateOrganizationDto, adminId: string) {
    const org = await this.prisma.organization.create({
      data: {
        name: dto.name,
        slug: dto.slug,
        description: dto.description,
        contactEmail: dto.ownerEmail.toLowerCase(),
        contactPhone: dto.contactPhone,
      },
    });
    const invite = await this.auth.createInvitation({
      email: dto.ownerEmail,
      organizationId: org.id,
      orgRole: 'ORG_OWNER',
      invitedById: adminId,
    });
    return { organization: org, inviteUrl: invite.url, inviteExpiresAt: invite.expiresAt };
  }

  list() {
    return this.prisma.organization.findMany({
      orderBy: { createdAt: 'desc' },
      include: { _count: { select: { events: true, members: true } } },
    });
  }

  async get(id: string) {
    const org = await this.prisma.organization.findUnique({
      where: { id },
      include: {
        members: { include: { user: { select: { id: true, email: true, displayName: true, phone: true } } } },
        invitations: { where: { acceptedAt: null }, select: { id: true, email: true, orgRole: true, expiresAt: true } },
        _count: { select: { events: true } },
      },
    });
    if (!org) throw new NotFoundException();
    return org;
  }

  /** Approving KYC makes the organizer "verified": their events then publish without review. */
  setKyc(id: string, dto: SetKycDto) {
    return this.prisma.organization.update({
      where: { id },
      data: {
        kycStatus: dto.status,
        kycNote: dto.note ?? null,
        verifiedAt: dto.status === 'APPROVED' ? new Date() : null,
      },
    });
  }

  async inviteMember(organizationId: string, dto: InviteMemberDto, invitedById: string) {
    const invite = await this.auth.createInvitation({ email: dto.email, organizationId, orgRole: dto.role, invitedById });
    return { inviteUrl: invite.url, inviteExpiresAt: invite.expiresAt };
  }
}

@ApiTags('admin')
@Controller('admin/organizations')
@Auth('PLATFORM_ADMIN')
export class AdminOrganizationsController {
  constructor(private readonly orgs: OrganizationsService) {}

  @Post()
  create(@Body() dto: CreateOrganizationDto, @CurrentUser() user: AuthUser) {
    return this.orgs.create(dto, user.sub);
  }

  @Get()
  list() {
    return this.orgs.list();
  }

  @Get(':id')
  get(@Param('id', ParseUUIDPipe) id: string) {
    return this.orgs.get(id);
  }

  @Patch(':id/kyc')
  setKyc(@Param('id', ParseUUIDPipe) id: string, @Body() dto: SetKycDto) {
    return this.orgs.setKyc(id, dto);
  }
}

/** Organization owners can invite their own team. */
@ApiTags('organizer')
@Controller('organizations/:orgId')
@Auth()
export class OrganizationMembersController {
  constructor(
    private readonly orgs: OrganizationsService,
    private readonly access: OrgAccessService,
  ) {}

  @Get()
  async get(@Param('orgId', ParseUUIDPipe) orgId: string, @CurrentUser() user: AuthUser) {
    await this.access.assert(user, orgId, ['ORG_OWNER', 'ORG_MANAGER', 'ORG_FINANCE']);
    return this.orgs.get(orgId);
  }

  @Post('invitations')
  async invite(@Param('orgId', ParseUUIDPipe) orgId: string, @Body() dto: InviteMemberDto, @CurrentUser() user: AuthUser) {
    await this.access.assert(user, orgId, ['ORG_OWNER']);
    return this.orgs.inviteMember(orgId, dto, user.sub);
  }
}

@Module({
  imports: [AuthModule],
  controllers: [AdminOrganizationsController, OrganizationMembersController],
  providers: [OrganizationsService],
})
export class OrganizationsModule {}
