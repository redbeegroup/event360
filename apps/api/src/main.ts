import 'reflect-metadata';
import { Logger, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
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
  const app = await NestFactory.create(AppModule, { bufferLogs: false });
  app.use(helmet());
  app.enableCors({ origin: process.env.CORS_ORIGINS?.split(',') ?? true, credentials: true });
  app.setGlobalPrefix('v1', { exclude: ['healthz', 'readyz'] });
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
  app.enableShutdownHooks();

  if (role === 'api') {
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
