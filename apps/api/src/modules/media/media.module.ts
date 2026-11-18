import { GetObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import {
  BadRequestException,
  Controller,
  Get,
  Global,
  Injectable,
  Module,
  NotFoundException,
  Param,
  Post,
  Res,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { FileInterceptor } from '@nestjs/platform-express';
import { ApiBody, ApiConsumes, ApiTags } from '@nestjs/swagger';
import { randomUUID } from 'crypto';
import type { Response } from 'express';
import { Auth } from '../../common/auth';

const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
const IMAGE_TYPES: Record<string, { ext: string; magic: (b: Buffer) => boolean }> = {
  'image/jpeg': { ext: 'jpg', magic: (b) => b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff },
  'image/png': { ext: 'png', magic: (b) => b.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) },
  'image/webp': { ext: 'webp', magic: (b) => b.subarray(0, 4).toString() === 'RIFF' && b.subarray(8, 12).toString() === 'WEBP' },
};
const KEY_RE = /^[a-z0-9][a-z0-9/._-]{5,200}$/;

/**
 * Images live in SeaweedFS (S3 API) under `<S3_PREFIX>/images/...` — one bucket, one prefix per environment.
 * Uploads go through the API (no bucket CORS needed); reads redirect to a short-lived presigned URL.
 */
@Injectable()
export class MediaService {
  private readonly s3: S3Client;
  private readonly bucket: string;
  private readonly prefix: string;
  private readonly publicApiUrl: string;

  constructor(config: ConfigService) {
    this.s3 = new S3Client({
      endpoint: config.get('S3_ENDPOINT'),
      region: config.get('S3_REGION') ?? 'us-east-1',
      forcePathStyle: true,
      credentials: {
        accessKeyId: config.get('S3_ACCESS_KEY_ID') ?? '',
        secretAccessKey: config.get('S3_SECRET_ACCESS_KEY') ?? '',
      },
    });
    this.bucket = config.get('S3_BUCKET') ?? 'event360';
    this.prefix = (config.get<string>('S3_PREFIX') ?? 'dev').replace(/\/+$/, '');
    this.publicApiUrl = (config.get<string>('PUBLIC_API_URL') ?? '').replace(/\/+$/, '');
  }

  /** Public, stable URL for a stored key (served by GET /v1/media/<key>). */
  url(key: string | null | undefined): string | null {
    return key ? `${this.publicApiUrl}/v1/media/${key}` : null;
  }

  isOwnKey(key: string): boolean {
    return KEY_RE.test(key) && key.startsWith(`${this.prefix}/`) && !key.includes('..');
  }

  async uploadImage(file: Express.Multer.File | undefined): Promise<{ key: string; url: string }> {
    if (!file) throw new BadRequestException('file is required');
    const type = IMAGE_TYPES[file.mimetype];
    if (!type || !type.magic(file.buffer)) throw new BadRequestException('Only JPEG, PNG or WebP images are allowed');
    const now = new Date();
    const key = `${this.prefix}/images/${now.getUTCFullYear()}/${String(now.getUTCMonth() + 1).padStart(2, '0')}/${randomUUID()}.${type.ext}`;
    await this.s3.send(
      new PutObjectCommand({ Bucket: this.bucket, Key: key, Body: file.buffer, ContentType: file.mimetype, CacheControl: 'public, max-age=31536000, immutable' }),
    );
    return { key, url: this.url(key)! };
  }

  presignedGet(key: string): Promise<string> {
    return getSignedUrl(this.s3, new GetObjectCommand({ Bucket: this.bucket, Key: key }), { expiresIn: 3600 });
  }
}

@ApiTags('media')
@Controller('media')
export class MediaController {
  constructor(private readonly media: MediaService) {}

  @Post('images')
  @Auth()
  @ApiConsumes('multipart/form-data')
  @ApiBody({ schema: { type: 'object', properties: { file: { type: 'string', format: 'binary' } } } })
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX_IMAGE_BYTES, files: 1 } }))
  upload(@UploadedFile() file: Express.Multer.File) {
    return this.media.uploadImage(file);
  }

  /** Redirects to a presigned SeaweedFS URL (valid 1h). */
  @Get('*')
  async get(@Param('0') key: string, @Res() res: Response) {
    if (!this.media.isOwnKey(key)) throw new NotFoundException();
    res.setHeader('Cache-Control', 'public, max-age=1800');
    res.redirect(302, await this.media.presignedGet(key));
  }
}

@Global()
@Module({ controllers: [MediaController], providers: [MediaService], exports: [MediaService] })
export class MediaModule {}
