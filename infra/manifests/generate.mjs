#!/usr/bin/env node
/**
 * Generates the plain Kubernetes manifests that Portainer GitOps applies:
 *   deploy/<env>/event360.yaml  for each environment in envs.json
 *
 * Usage:
 *   node infra/manifests/generate.mjs                 write all files
 *   node infra/manifests/generate.mjs --check         exit 1 if committed files are stale
 *   node infra/manifests/generate.mjs --set-tag dev=<tag>   update envs.json, then write
 *
 * Secrets are NOT generated here. Each namespace must already contain the Secret
 * `event360-secrets` (shape: infra/k8s/secrets.example.yaml).
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import yaml from 'js-yaml';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..', '..');
const ENVS_FILE = join(HERE, 'envs.json');
const SECRET = 'event360-secrets';
const PART_OF = 'event360';

const SHA_RE = /^[0-9a-f]{40}$/;

const labels = (name) => ({ 'app.kubernetes.io/name': name, 'app.kubernetes.io/part-of': PART_OF });

function meta(name, ns, extra = {}) {
  return { name, namespace: ns, labels: labels(name), ...extra };
}

function service(name, ns, port, annotations) {
  return {
    apiVersion: 'v1',
    kind: 'Service',
    metadata: meta(name, ns, annotations ? { annotations } : {}),
    spec: { selector: { 'app.kubernetes.io/name': name }, ports: [{ name: 'http', port, targetPort: 'http' }] },
  };
}

function backendEnv(env) {
  return [
    { name: 'NODE_ENV', value: 'production' },
    { name: 'PORT', value: '3000' },
    // NPMPlus → Traefik → pod
    { name: 'TRUST_PROXY', value: '2' },
    { name: 'OTP_TTL_SECONDS', value: '300' },
    { name: 'OTP_DEV_ECHO', value: String(env.otpDevEcho) },
    { name: 'JWT_ACCESS_TTL', value: '15m' },
    { name: 'CORS_ORIGINS', value: `https://portal.${env.domain}` },
  ];
}

/** Keeps pods off nodes listed in envs.json `avoidNodes` (e.g. a node with broken networking). */
function avoidNodesAffinity(config, extra = []) {
  const nodes = [...new Set([...(config.avoidNodes ?? []), ...extra])];
  if (nodes.length === 0) return {};
  return {
    affinity: {
      nodeAffinity: {
        requiredDuringSchedulingIgnoredDuringExecution: {
          nodeSelectorTerms: [{ matchExpressions: [{ key: 'kubernetes.io/hostname', operator: 'NotIn', values: nodes }] }],
        },
      },
    },
  };
}

function deployment({ name, ns, image, pullPolicy, replicas, env, envFrom, runAsUser, probes, initContainers, resources, config }) {
  return {
    apiVersion: 'apps/v1',
    kind: 'Deployment',
    metadata: meta(name, ns),
    spec: {
      replicas,
      revisionHistoryLimit: 5,
      selector: { matchLabels: { 'app.kubernetes.io/name': name } },
      template: {
        metadata: { labels: labels(name) },
        spec: {
          securityContext: { runAsNonRoot: true, runAsUser, runAsGroup: runAsUser, fsGroup: runAsUser },
          ...avoidNodesAffinity(config),
          ...(initContainers ? { initContainers } : {}),
          containers: [
            {
              name,
              image,
              imagePullPolicy: pullPolicy,
              ports: [{ name: 'http', containerPort: 3000 }],
              env,
              ...(envFrom ? { envFrom } : {}),
              ...probes,
              resources,
              securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: ['ALL'] } },
            },
          ],
        },
      },
    },
  };
}

export function buildManifests(envName, config) {
  const env = config.environments[envName];
  if (!env) throw new Error(`Unknown environment: ${envName}`);
  const ns = env.namespace;
  const pullPolicy = SHA_RE.test(env.imageTag) ? 'IfNotPresent' : 'Always';
  const apiImage = `${config.registry}/event360-api:${env.imageTag}`;
  const webImage = `${config.registry}/event360-web:${env.imageTag}`;
  const envFrom = [{ secretRef: { name: SECRET } }];
  const backendProbes = {
    livenessProbe: { httpGet: { path: '/healthz', port: 'http' }, periodSeconds: 10, failureThreshold: 3 },
    readinessProbe: { httpGet: { path: '/readyz', port: 'http' }, periodSeconds: 5, failureThreshold: 3 },
  };
  const small = { requests: { cpu: '100m', memory: '256Mi' }, limits: { memory: '512Mi' } };
  const medium = { requests: { cpu: '200m', memory: '384Mi' }, limits: { memory: '768Mi' } };

  const objects = [];

  // ── Redis (dedicated; BullMQ requires noeviction) ──
  objects.push(
    {
      apiVersion: 'apps/v1',
      kind: 'StatefulSet',
      metadata: meta('redis', ns),
      spec: {
        serviceName: 'redis',
        replicas: 1,
        selector: { matchLabels: { 'app.kubernetes.io/name': 'redis' } },
        template: {
          metadata: { labels: labels('redis') },
          spec: {
            securityContext: { runAsNonRoot: true, runAsUser: 999, runAsGroup: 999, fsGroup: 999 },
            // Pods with a block-storage volume also avoid nodes that can't mount it (storageAvoidNodes)
            ...avoidNodesAffinity(config, config.storageAvoidNodes ?? []),
            containers: [
              {
                name: 'redis',
                image: 'redis:7.4-alpine',
                command: ['sh', '-c'],
                args: [
                  'exec redis-server --appendonly yes --maxmemory-policy noeviction --requirepass "$REDIS_PASSWORD"',
                ],
                env: [{ name: 'REDIS_PASSWORD', valueFrom: { secretKeyRef: { name: SECRET, key: 'REDIS_PASSWORD' } } }],
                ports: [{ name: 'redis', containerPort: 6379 }],
                readinessProbe: {
                  exec: { command: ['sh', '-c', 'redis-cli -a "$REDIS_PASSWORD" --no-auth-warning ping | grep -q PONG'] },
                  periodSeconds: 10,
                },
                volumeMounts: [{ name: 'data', mountPath: '/data' }],
                resources: { requests: { cpu: '50m', memory: '128Mi' }, limits: { memory: '512Mi' } },
                securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: ['ALL'] } },
              },
            ],
          },
        },
        volumeClaimTemplates: [
          {
            metadata: { name: 'data' },
            spec: {
              accessModes: ['ReadWriteOnce'],
              storageClassName: config.storageClass,
              resources: { requests: { storage: '2Gi' } },
            },
          },
        ],
      },
    },
    {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: meta('redis', ns),
      spec: { selector: { 'app.kubernetes.io/name': 'redis' }, ports: [{ name: 'redis', port: 6379, targetPort: 'redis' }] },
    },
  );

  // ── API (runs migrations + idempotent seed before starting) ──
  objects.push(
    deployment({
      name: 'api',
      ns,
      image: apiImage,
      pullPolicy,
      config,
      replicas: env.replicas.api,
      env: [...backendEnv(env), { name: 'APP_ROLE', value: 'api' }],
      envFrom,
      runAsUser: 10001,
      probes: backendProbes,
      resources: medium,
      initContainers: [
        {
          name: 'migrate',
          image: apiImage,
          imagePullPolicy: pullPolicy,
          command: ['sh', '-c', 'npx prisma migrate deploy && node dist/seed.js'],
          envFrom,
          securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: ['ALL'] } },
          resources: medium,
        },
      ],
    }),
    service('api', ns, 3000),
  );

  // ── Realtime (Socket.IO) and worker share the API image ──
  for (const role of ['realtime', 'worker']) {
    objects.push(
      deployment({
        name: role,
        ns,
        image: apiImage,
        pullPolicy,
        config,
        replicas: env.replicas[role],
        env: [...backendEnv(env), { name: 'APP_ROLE', value: role }],
        envFrom,
        runAsUser: 10001,
        probes: backendProbes,
        resources: role === 'worker' ? medium : small,
      }),
    );
  }
  objects.push(service('realtime', ns, 3000, { 'traefik.ingress.kubernetes.io/service.sticky.cookie': 'true' }));

  // ── Web portal ──
  objects.push(
    deployment({
      name: 'web',
      ns,
      image: webImage,
      pullPolicy,
      config,
      replicas: env.replicas.web,
      env: [{ name: 'API_URL', value: 'http://api:3000' }],
      runAsUser: 1000,
      probes: { readinessProbe: { httpGet: { path: '/', port: 'http' }, periodSeconds: 10 } },
      resources: small,
    }),
    service('web', ns, 3000),
  );

  // ── Ingress (Traefik; TLS terminated upstream by NPMPlus) ──
  const routes = [
    ['api', 'api'],
    ['ws', 'realtime'],
    ['portal', 'web'],
  ];
  objects.push({
    apiVersion: 'networking.k8s.io/v1',
    kind: 'Ingress',
    metadata: meta('event360', ns),
    spec: {
      ingressClassName: 'traefik',
      rules: routes.map(([host, svc]) => ({
        host: `${host}.${env.domain}`,
        http: {
          paths: [{ path: '/', pathType: 'Prefix', backend: { service: { name: svc, port: { name: 'http' } } } }],
        },
      })),
    },
  });

  // ── Only Traefik and pods in this namespace may connect ──
  objects.push({
    apiVersion: 'networking.k8s.io/v1',
    kind: 'NetworkPolicy',
    metadata: meta('event360-default', ns),
    spec: {
      podSelector: {},
      policyTypes: ['Ingress'],
      ingress: [
        {
          from: [
            { podSelector: {} },
            { namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': 'traefik' } } },
          ],
        },
      ],
    },
  });

  return objects;
}

export function render(envName, config) {
  const header =
    `# GENERATED by infra/manifests/generate.mjs from infra/manifests/envs.json — do not edit.\n` +
    `# Applied by Portainer GitOps into namespace ${config.environments[envName].namespace}.\n`;
  return header + buildManifests(envName, config).map((o) => '---\n' + yaml.dump(o, { lineWidth: 120, noRefs: true })).join('');
}

const outPath = (envName) => join(ROOT, 'deploy', envName, 'event360.yaml');

function main(argv) {
  const config = JSON.parse(readFileSync(ENVS_FILE, 'utf8'));
  const setTag = argv.indexOf('--set-tag');
  if (setTag !== -1) {
    const [envName, tag] = (argv[setTag + 1] ?? '').split('=');
    if (!config.environments[envName] || !tag) throw new Error('--set-tag expects <env>=<tag>');
    config.environments[envName].imageTag = tag;
    writeFileSync(ENVS_FILE, JSON.stringify(config, null, 2) + '\n');
  }

  let stale = false;
  for (const envName of Object.keys(config.environments)) {
    const file = outPath(envName);
    const content = render(envName, config);
    if (argv.includes('--check')) {
      if (!existsSync(file) || readFileSync(file, 'utf8') !== content) {
        console.error(`stale: ${file}`);
        stale = true;
      }
    } else {
      mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, content);
      console.log(`wrote ${file}`);
    }
  }
  if (stale) {
    console.error('Run: node infra/manifests/generate.mjs');
    process.exit(1);
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main(process.argv.slice(2));
