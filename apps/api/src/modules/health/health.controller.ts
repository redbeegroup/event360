import { Controller, Get, ServiceUnavailableException } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { PrismaService } from '../prisma/prisma.service';

@ApiTags('health')
@Controller()
export class HealthController {
  constructor(private readonly prisma: PrismaService) {}

  /** Liveness: process is up. */
  @Get('healthz')
  live() {
    return { status: 'ok', role: process.env.APP_ROLE ?? 'api' };
  }

  /** Readiness: database reachable (through PgBouncer). */
  @Get('readyz')
  async ready() {
    try {
      await this.prisma.$queryRaw`SELECT 1`;
      return { status: 'ready' };
    } catch {
      throw new ServiceUnavailableException({ status: 'db_unavailable' });
    }
  }
}
