import 'reflect-metadata';
import { Logger, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import helmet from 'helmet';
import { AppModule } from './app.module';

/**
 * One image, three workloads (see ADR-0001 §1):
 *   APP_ROLE=api       HTTP API (default)
 *   APP_ROLE=worker    queues & cron (BullMQ) — no HTTP listener besides health
 *   APP_ROLE=realtime  Socket.IO gateway
 */
async function bootstrap() {
  const role = process.env.APP_ROLE ?? 'api';
  const app = await NestFactory.create<NestExpressApplication>(AppModule, { bufferLogs: false });
  // Behind NPMPlus → Traefik: trust N proxy hops so req.ip is the real client IP
  // (used by rate limiting). Never trust arbitrary X-Forwarded-For when exposed directly.
  const trustProxy = Number(process.env.TRUST_PROXY ?? 0);
  if (trustProxy > 0) app.getHttpAdapter().getInstance().set('trust proxy', trustProxy);
  // Images (/v1/media/…) are embedded by our other sites (event360.app, the web app, the portal), so allow
  // cross-origin embedding; reading API data from other origins is still governed by CORS.
  app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
  app.enableCors({ origin: process.env.CORS_ORIGINS?.split(',') ?? true, credentials: true });
  app.setGlobalPrefix('v1', { exclude: ['healthz', 'readyz'] });
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
  app.enableShutdownHooks();

  // API docs on dev only (the route list helps attackers more than anyone else on prod)
  if (role === 'api' && process.env.ENV_NAME !== 'prod') {
    const config = new DocumentBuilder()
      .setTitle('Event 360 API')
      .setVersion('0.1.0')
      .addBearerAuth()
      .build();
    SwaggerModule.setup('docs', app, SwaggerModule.createDocument(app, config));
  }

  const port = Number(process.env.PORT ?? 3000);
  await app.listen(port);
  Logger.log(`Event 360 [${role}] listening on :${port}`, 'Bootstrap');
}

bootstrap();
