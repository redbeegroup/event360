import { ApiProperty } from '@nestjs/swagger';
import { IsString, Length, Matches } from 'class-validator';

export class RequestOtpDto {
  @ApiProperty({ example: '09 123 456 789' })
  @IsString()
  @Length(7, 20)
  phone: string;
}

export class VerifyOtpDto {
  @ApiProperty({ example: '09123456789' })
  @IsString()
  @Length(7, 20)
  phone: string;

  @ApiProperty({ example: '123456' })
  @Matches(/^\d{6}$/)
  code: string;
}

export class RefreshDto {
  @ApiProperty()
  @IsString()
  refreshToken: string;
}
