import { Injectable, Logger } from '@nestjs/common';
import { existsSync, readFileSync } from 'fs';
import { request } from 'https';

const SA = '/var/run/secrets/kubernetes.io/serviceaccount';

export interface JobStatus {
  name: string;
  active: number;
  succeeded: number;
  failed: number;
}

/**
 * Minimal in-cluster client for batch/v1 Jobs, using the pod's ServiceAccount token.
 * The API's Role only allows jobs in its own namespace. Outside a cluster (tests, local dev) it is disabled.
 */
@Injectable()
export class K8sJobsService {
  private readonly logger = new Logger(K8sJobsService.name);
  readonly enabled = existsSync(`${SA}/token`) && !!process.env.KUBERNETES_SERVICE_HOST;
  readonly namespace = this.enabled ? readFileSync(`${SA}/namespace`, 'utf8').trim() : 'local';

  private call<T>(method: string, path: string, body?: unknown): Promise<{ status: number; body: T }> {
    if (!this.enabled) return Promise.reject(new Error('Kubernetes API not available (not running in the cluster)'));
    const data = body === undefined ? undefined : JSON.stringify(body);
    return new Promise((resolve, reject) => {
      const req = request(
        {
          host: process.env.KUBERNETES_SERVICE_HOST,
          port: Number(process.env.KUBERNETES_SERVICE_PORT ?? 443),
          path,
          method,
          ca: readFileSync(`${SA}/ca.crt`),
          headers: {
            authorization: `Bearer ${readFileSync(`${SA}/token`, 'utf8').trim()}`,
            accept: 'application/json',
            ...(data ? { 'content-type': 'application/json', 'content-length': Buffer.byteLength(data) } : {}),
          },
          timeout: 15_000,
        },
        (res) => {
          const chunks: Buffer[] = [];
          res.on('data', (c) => chunks.push(c));
          res.on('end', () => {
            const text = Buffer.concat(chunks).toString();
            let parsed: unknown = text;
            try {
              parsed = text ? JSON.parse(text) : null;
            } catch {
              /* keep text */
            }
            resolve({ status: res.statusCode ?? 0, body: parsed as T });
          });
        },
      );
      req.on('timeout', () => req.destroy(new Error('Kubernetes API timeout')));
      req.on('error', reject);
      if (data) req.write(data);
      req.end();
    });
  }

  async createJob(job: Record<string, unknown>): Promise<void> {
    const r = await this.call<{ message?: string }>('POST', `/apis/batch/v1/namespaces/${this.namespace}/jobs`, job);
    if (r.status !== 201) throw new Error(`Job create failed (${r.status}): ${r.body?.message ?? ''}`);
  }

  async getJob(name: string): Promise<JobStatus | null> {
    const r = await this.call<{ status?: { active?: number; succeeded?: number; failed?: number } }>(
      'GET',
      `/apis/batch/v1/namespaces/${this.namespace}/jobs/${name}`,
    );
    if (r.status === 404) return null;
    if (r.status !== 200) throw new Error(`Job get failed (${r.status})`);
    const s = r.body?.status ?? {};
    return { name, active: s.active ?? 0, succeeded: s.succeeded ?? 0, failed: s.failed ?? 0 };
  }

  async deleteJob(name: string): Promise<void> {
    const r = await this.call('DELETE', `/apis/batch/v1/namespaces/${this.namespace}/jobs/${name}?propagationPolicy=Background`);
    if (![200, 202, 404].includes(r.status)) this.logger.warn(`Job delete ${name}: HTTP ${r.status}`);
  }
}
