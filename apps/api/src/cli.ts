/**
 * Operational CLI (runs inside the API image, e.g. as a one-off Kubernetes Job):
 *   node dist/cli.js invite-admin <email>   → prints a one-time link to create a platform admin
 */
import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { AuthService } from './modules/auth/auth.service';

async function main() {
  const [cmd, arg] = process.argv.slice(2);
  if (cmd !== 'invite-admin' || !arg || !arg.includes('@')) {
    console.error('Usage: node dist/cli.js invite-admin <email>');
    process.exit(2);
  }
  const app = await NestFactory.createApplicationContext(AppModule, { logger: ['error', 'warn'] });
  const invite = await app.get(AuthService).createInvitation({ email: arg, platformRole: 'PLATFORM_ADMIN' });
  console.log(`ADMIN_INVITE_URL=${invite.url}`);
  console.log(`EXPIRES_AT=${invite.expiresAt.toISOString()}`);
  await app.close();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
