import {
  applyDecorators,
  CanActivate,
  createParamDecorator,
  ExecutionContext,
  ForbiddenException,
  Injectable,
  SetMetadata,
  UnauthorizedException,
  UseGuards,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { ApiBearerAuth } from '@nestjs/swagger';
import type { PlatformRole } from '@prisma/client';

export interface AuthUser {
  sub: string;
  roles: PlatformRole[];
}

/** The authenticated user (`{ sub, roles }`) from the access token. */
export const CurrentUser = createParamDecorator((_: unknown, ctx: ExecutionContext): AuthUser => {
  return ctx.switchToHttp().getRequest().user;
});

const ROLES_KEY = 'platformRoles';

/** Verifies the Bearer token and, if `@Auth(...roles)` lists roles, requires one of them. */
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly jwt: JwtService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const req = ctx.switchToHttp().getRequest();
    const [type, token] = (req.headers.authorization ?? '').split(' ');
    if (type !== 'Bearer' || !token) throw new UnauthorizedException();
    try {
      req.user = await this.jwt.verifyAsync<AuthUser>(token);
    } catch {
      throw new UnauthorizedException();
    }
    const required = this.reflector.getAllAndOverride<PlatformRole[]>(ROLES_KEY, [ctx.getHandler(), ctx.getClass()]);
    if (required?.length && !required.some((r) => req.user.roles?.includes(r))) {
      throw new ForbiddenException('Insufficient role');
    }
    return true;
  }
}

/** `@Auth()` = any signed-in user; `@Auth('PLATFORM_ADMIN')` = admins only. */
export function Auth(...roles: PlatformRole[]) {
  return applyDecorators(SetMetadata(ROLES_KEY, roles), UseGuards(AuthGuard), ApiBearerAuth());
}
