/** @type {import('next').NextConfig} */
export default {
  output: 'standalone',
  reactStrictMode: true,
  // Cover images (max 5 MB) are posted through server actions to the API.
  experimental: { serverActions: { bodySizeLimit: '6mb' } },
  images: { unoptimized: true },
};
