import { Body, Controller, Get, HttpCode, Param, Post } from '@nestjs/common';
import { Auth, AuthUser, CurrentUser } from '../../common/auth';
import { ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { AuthService } from './auth.service';
import { AcceptInviteDto, PasswordLoginDto, RefreshDto, RequestOtpDto, VerifyOtpDto } from './dto';

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post('otp/request')
  @HttpCode(200)
  // Per-IP ceiling is generous (carrier NAT); the real limit is per phone number in AuthService.
  @Throttle({ default: { ttl: 60_000, limit: 30 } })
  request(@Body() dto: RequestOtpDto) {
    return this.auth.requestOtp(dto.phone);
  }

  @Post('otp/verify')
  @HttpCode(200)
  @Throttle({ default: { ttl: 60_000, limit: 30 } })
  verify(@Body() dto: VerifyOtpDto) {
    return this.auth.verifyOtp(dto.phone, dto.code);
  }

  @Post('refresh')
  @HttpCode(200)
  refresh(@Body() dto: RefreshDto) {
    return this.auth.refresh(dto.refreshToken);
  }

  /** Signs out: the refresh token stops working (the short-lived access token simply expires). */
  @Post('logout')
  @HttpCode(204)
  async logout(@Body() dto: RefreshDto) {
    await this.auth.logout(dto.refreshToken);
  }

  @Post('password/login')
  @HttpCode(200)
  @Throttle({ default: { ttl: 60_000, limit: 10 } })
  passwordLogin(@Body() dto: PasswordLoginDto) {
    return this.auth.passwordLogin(dto.email, dto.password);
  }

  @Get('invitations/:token')
  getInvitation(@Param('token') token: string) {
    return this.auth.getInvitation(token);
  }

  @Post('invitations/:token/accept')
  @HttpCode(200)
  @Throttle({ default: { ttl: 60_000, limit: 10 } })
  acceptInvitation(@Param('token') token: string, @Body() dto: AcceptInviteDto) {
    return this.auth.acceptInvitation(token, dto.password, dto.displayName);
  }

  @Get('me')
  @Auth()
  me(@CurrentUser() user: AuthUser) {
    return this.auth.me(user.sub);
  }
}
