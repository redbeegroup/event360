import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { DeliveryMode, EventFormat, EventVisibility } from '@prisma/client';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsUrl,
  IsDateString,
  IsEnum,
  IsIn,
  IsInt,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsString,
  IsUUID,
  Length,
  Matches,
  Max,
  MaxLength,
  Min,
  ValidateNested,
} from 'class-validator';

export class VenueDto {
  @ApiProperty() @IsString() @Length(2, 160) name: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(160) nameMy?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(300) address?: string;
  @ApiProperty({ example: 'Yangon' }) @IsString() @Length(2, 80) city: string;
  @ApiPropertyOptional() @IsOptional() @IsLatitude() latitude?: number;
  @ApiPropertyOptional() @IsOptional() @IsLongitude() longitude?: number;
  @ApiPropertyOptional({ description: 'Google Maps (or other) link to the venue' }) @IsOptional() @IsUrl({ require_protocol: true }) @MaxLength(500) mapUrl?: string;
  @ApiPropertyOptional({ description: 'How to get there, landmarks' }) @IsOptional() @IsString() @MaxLength(1000) directions?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(1000) directionsMy?: string;
}

export class CreateEventDto {
  @ApiProperty() @IsUUID() categoryId: string;
  @ApiProperty({ description: 'English title (also used for the URL slug)' }) @IsString() @Length(3, 160) title: string;
  @ApiPropertyOptional({ description: 'Myanmar title (Unicode)' }) @IsOptional() @IsString() @MaxLength(160) titleMy?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(300) summary?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(300) summaryMy?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(20000) description?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(20000) descriptionMy?: string;
  @ApiPropertyOptional({ description: 'Media key returned by POST /v1/media/images' })
  @IsOptional()
  @Matches(/^[a-z0-9][a-z0-9/._-]{5,200}$/)
  coverImageKey?: string;
  @ApiProperty({ enum: EventFormat }) @IsEnum(EventFormat) format: EventFormat;
  @ApiPropertyOptional({ enum: EventVisibility }) @IsOptional() @IsEnum(EventVisibility) visibility?: EventVisibility;
  @ApiProperty() @IsDateString() startsAt: string;
  @ApiProperty() @IsDateString() endsAt: string;
  @ApiPropertyOptional({ type: VenueDto }) @IsOptional() @ValidateNested() @Type(() => VenueDto) venue?: VenueDto;

  // ── Practical info ──
  @ApiPropertyOptional({ description: 'Minimum age; omit for all ages' }) @IsOptional() @IsInt() @Min(0) @Max(99) ageMin?: number;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(300) dressCode?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(300) dressCodeMy?: string;
  @ApiPropertyOptional({ example: 'Myanmar, English' }) @IsOptional() @IsString() @MaxLength(200) languages?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(200) languagesMy?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(500) parking?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(500) parkingMy?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(500) accessibility?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(500) accessibilityMy?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(500) whatToBring?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(500) whatToBringMy?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(10000) terms?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(10000) termsMy?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(5000) refundPolicy?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(5000) refundPolicyMy?: string;
  @ApiPropertyOptional({ description: 'Ticket holders may pass tickets to someone else' }) @IsOptional() @IsBoolean() transfersEnabled?: boolean;
  @ApiPropertyOptional({ description: 'No transfers this many hours before the start' }) @IsOptional() @IsInt() @Min(0) @Max(168) transferCutoffHours?: number;
}

export class UpdateEventDto extends PartialType(CreateEventDto) {}

export class TicketTypeDto {
  @ApiProperty() @IsString() @Length(1, 80) name: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(80) nameMy?: string;
  @ApiProperty({ description: 'Price in MMK; 0 = free' }) @IsInt() @Min(0) @Max(100_000_000) priceMmk: number;
  @ApiProperty() @IsInt() @Min(1) @Max(1_000_000) quota: number;
  @ApiPropertyOptional({ default: 10 }) @IsOptional() @IsInt() @Min(1) @Max(50) maxPerOrder?: number;
  @ApiPropertyOptional({ enum: DeliveryMode }) @IsOptional() @IsEnum(DeliveryMode) deliveryMode?: DeliveryMode;
  @ApiPropertyOptional() @IsOptional() @IsDateString() salesStartAt?: string;
  @ApiPropertyOptional() @IsOptional() @IsDateString() salesEndAt?: string;
}

export class UpdateTicketTypeDto extends PartialType(TicketTypeDto) {}

export class ReasonDto {
  @ApiProperty() @IsString() @Length(3, 1000) reason: string;
}

export class ListEventsQuery {
  @ApiPropertyOptional({ description: 'Search title/summary (English or Myanmar)' }) @IsOptional() @IsString() @MaxLength(100) q?: string;
  @ApiPropertyOptional({ description: 'Category or sub-category slug' }) @IsOptional() @IsString() @MaxLength(80) category?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(80) city?: string;
  @ApiPropertyOptional() @IsOptional() @IsDateString() from?: string;
  @ApiPropertyOptional() @IsOptional() @IsDateString() to?: string;
  @ApiPropertyOptional() @IsOptional() @Type(() => String) @IsIn(['true', 'false']) free?: 'true' | 'false';
  @ApiPropertyOptional({ enum: EventFormat }) @IsOptional() @IsEnum(EventFormat) format?: EventFormat;
  @ApiPropertyOptional({ default: 1 }) @IsOptional() @Type(() => Number) @IsInt() @Min(1) page?: number;
  @ApiPropertyOptional({ default: 20 }) @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(50) limit?: number;
}

export class RegisterDto {
  @ApiProperty() @IsUUID() ticketTypeId: string;
  @ApiProperty({ default: 1 }) @IsInt() @Min(1) @Max(50) quantity: number;
}

export class AdminEventsQuery {
  @ApiPropertyOptional({ default: 'SUBMITTED' })
  @IsOptional()
  @IsIn(['DRAFT', 'SUBMITTED', 'APPROVED', 'REJECTED', 'PUBLISHED', 'ONGOING', 'COMPLETED', 'CANCELLED'])
  status?: string;
}

// ── Replace-all lists (schedule, lineup, gallery, FAQ) ──

const MEDIA_KEY = /^[a-z0-9][a-z0-9/._-]{5,200}$/;

export class SessionItemDto {
  @ApiPropertyOptional({ description: 'Existing session id (kept, so its live channel survives edits)' }) @IsOptional() @IsUUID() id?: string;
  @ApiProperty() @IsString() @Length(1, 160) title: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(160) titleMy?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(1000) description?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(1000) descriptionMy?: string;
  @ApiPropertyOptional({ example: 'Main stage' }) @IsOptional() @IsString() @MaxLength(120) location?: string;
  @ApiProperty() @IsDateString() startsAt: string;
  @ApiProperty() @IsDateString() endsAt: string;
}
export class SessionsDto {
  @ApiProperty({ type: [SessionItemDto] }) @IsArray() @ArrayMaxSize(100) @ValidateNested({ each: true }) @Type(() => SessionItemDto) items: SessionItemDto[];
}

export class PerformerItemDto {
  @ApiProperty() @IsString() @Length(1, 120) name: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(120) nameMy?: string;
  @ApiPropertyOptional({ example: 'Headliner' }) @IsOptional() @IsString() @MaxLength(80) role?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(80) roleMy?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(1000) bio?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(1000) bioMy?: string;
  @ApiPropertyOptional({ description: 'Media key from POST /v1/media/images' }) @IsOptional() @Matches(MEDIA_KEY) photoKey?: string;
}
export class PerformersDto {
  @ApiProperty({ type: [PerformerItemDto] }) @IsArray() @ArrayMaxSize(50) @ValidateNested({ each: true }) @Type(() => PerformerItemDto) items: PerformerItemDto[];
}

export class MediaItemDto {
  @ApiProperty({ description: 'Media key from POST /v1/media/images' }) @Matches(MEDIA_KEY) key: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(200) caption?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(200) captionMy?: string;
}
export class MediaListDto {
  @ApiProperty({ type: [MediaItemDto] }) @IsArray() @ArrayMaxSize(20) @ValidateNested({ each: true }) @Type(() => MediaItemDto) items: MediaItemDto[];
}

export class FaqItemDto {
  @ApiProperty() @IsString() @Length(2, 300) question: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(300) questionMy?: string;
  @ApiProperty() @IsString() @Length(1, 2000) answer: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(2000) answerMy?: string;
}
export class FaqsDto {
  @ApiProperty({ type: [FaqItemDto] }) @IsArray() @ArrayMaxSize(50) @ValidateNested({ each: true }) @Type(() => FaqItemDto) items: FaqItemDto[];
}

export class OrgProfileDto {
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(2000) description?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(2000) descriptionMy?: string;
  @ApiPropertyOptional() @IsOptional() @Matches(MEDIA_KEY) logoKey?: string;
  @ApiPropertyOptional() @IsOptional() @IsUrl({ require_protocol: true }) @MaxLength(300) website?: string;
  @ApiPropertyOptional() @IsOptional() @IsUrl({ require_protocol: true }) @MaxLength(300) facebookUrl?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(200) contactEmail?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(30) contactPhone?: string;
  @ApiPropertyOptional({ description: 'Show contact email/phone on the public organizer page' }) @IsOptional() @IsBoolean() showContact?: boolean;
}
