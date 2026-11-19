import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ThrottlerModule } from '@nestjs/throttler';
import { CommonModule } from './common/common.module';
import { AuthModule } from './modules/auth/auth.module';
import { EventsModule } from './modules/events/events.module';
import { MediaModule } from './modules/media/media.module';
import { OrganizationsModule } from './modules/organizations/organizations.module';
import { TicketsModule } from './modules/tickets/tickets.module';
import { CatalogModule } from './modules/catalog/catalog.module';
import { CheckinModule } from './modules/checkin/checkin.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { HealthModule } from './modules/health/health.module';
import { PrismaModule } from './modules/prisma/prisma.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 120 }]),
    PrismaModule,
    CommonModule,
    NotificationsModule,
    HealthModule,
    AuthModule,
    CatalogModule,
    MediaModule,
    OrganizationsModule,
    EventsModule,
    TicketsModule,
    CheckinModule,
  ],
})
export class AppModule {}
