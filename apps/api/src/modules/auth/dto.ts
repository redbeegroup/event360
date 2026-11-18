import { ApiProperty } from '@nestjs/swagger';
import { IsEmail, IsOptional, IsString, Length, Matches, MaxLength, MinLength } from 'class-validator';

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

export class PasswordLoginDto {
  @ApiProperty({ example: 'admin@example.com' })
  @IsEmail()
  email: string;

  @ApiProperty()
  @IsString()
  @MinLength(1)
  password: string;
}

export class AcceptInviteDto {
  @ApiProperty({ minLength: 10 })
  @IsString()
  @MinLength(10)
  @MaxLength(200)
  password: string;

  @ApiProperty({ required: false })
  @IsOptional()
  @IsString()
  @MaxLength(100)
  displayName?: string;
}
