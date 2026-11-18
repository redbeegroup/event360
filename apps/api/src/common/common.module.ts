import { Global, Module } from '@nestjs/common';
import { AuthGuard } from './auth';
import { OrgAccessService } from './org-access.service';

@Global()
@Module({ providers: [AuthGuard, OrgAccessService], exports: [AuthGuard, OrgAccessService] })
export class CommonModule {}
