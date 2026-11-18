import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { DeliveryMode, EventFormat, EventVisibility } from '@prisma/client';
import { Type } from 'class-transformer';
import {
  IsBoolean,
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
