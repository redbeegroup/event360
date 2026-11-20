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

function backendEnv(env, config) {
  const st = { ...(config.streaming ?? {}), ...(env.streaming ?? {}) };
  return [
    { name: 'NODE_ENV', value: 'production' },
    { name: 'PORT', value: '3000' },
    // NPMPlus → Traefik → pod
    { name: 'TRUST_PROXY', value: '2' },
    { name: 'OTP_TTL_SECONDS', value: '300' },
    { name: 'OTP_DEV_ECHO', value: String(env.otpDevEcho) },
    { name: 'PAYMENTS_MOCK', value: String(!!env.paymentsMock) },
    { name: 'JWT_ACCESS_TTL', value: '15m' },
    { name: 'CORS_ORIGINS', value: [`https://portal.${env.domain}`, ...(env.userWeb ? [`https://app.${env.domain}`] : [])].join(',') },
    // Used to build media URLs and invite links
    { name: 'PUBLIC_API_URL', value: `https://api.${env.domain}` },
    { name: 'PORTAL_URL', value: `https://portal.${env.domain}` },
    // Live streaming (SRS ingest + transcoder Jobs)
    { name: 'STREAM_RTMP_URL', value: `rtmp://${st.ingestHost}:${st.rtmpPort}/live` },
    { name: 'STREAM_SRT_URL', value: `srt://${st.ingestHost}:${st.srtPort}` },
    { name: 'SRS_INTERNAL_RTMP', value: 'rtmp://srs:1935' },
    { name: 'SRS_API_URL', value: 'http://srs:1985' },
    { name: 'MAX_LIVE_CHANNELS', value: String(st.maxLiveChannels ?? 1) },
    { name: 'FFMPEG_IMAGE', value: st.ffmpegImage },
    // Transcoder Jobs run the uploader from the same API image
    { name: 'API_IMAGE', value: `${config.registry}/event360-api:${env.imageTag}` },
    { name: 'MEDIA_AVOID_NODES', value: (config.avoidNodes ?? []).join(',') },
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

function deployment({ name, ns, image, pullPolicy, replicas, env, envFrom, runAsUser, probes, initContainers, resources, config, port = 3000, serviceAccountName }) {
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
          ...(serviceAccountName ? { serviceAccountName } : {}),
          securityContext: { runAsNonRoot: true, runAsUser, runAsGroup: runAsUser, fsGroup: runAsUser },
          ...avoidNodesAffinity(config),
          ...(initContainers ? { initContainers } : {}),
          containers: [
            {
              name,
              image,
              imagePullPolicy: pullPolicy,
              ports: [{ name: 'http', containerPort: port }],
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
      env: [...backendEnv(env, config), { name: 'APP_ROLE', value: 'api' }],
      envFrom,
      // Starts transcoder Jobs through the Kubernetes API (Role below: jobs in this namespace only)
      serviceAccountName: 'event360-api',
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
        env: [...backendEnv(env, config), { name: 'APP_ROLE', value: role }],
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
      env: [
        { name: 'API_URL', value: 'http://api:3000' },
        // Crew web preview link shown on the event page (dev only, served by user-web under /crew/)
        { name: 'CREW_APP_URL', value: env.userWeb ? `https://app.${env.domain}/crew/` : '' },
      ],
      runAsUser: 1000,
      probes: { readinessProbe: { httpGet: { path: '/', port: 'http' }, periodSeconds: 10 } },
      resources: small,
    }),
    service('web', ns, 3000),
  );

  // ── Public website (event360.app): server-rendered, no sign-in, reads the public API ──
  // (switched on per environment once that environment's image tag includes the site image)
  const site = { ...(config.site ?? {}), ...(env.site ?? {}) };
  if (site.enabled) objects.push(
    deployment({
      name: 'site',
      ns,
      image: `${config.registry}/event360-site:${env.imageTag}`,
      pullPolicy,
      config,
      replicas: env.replicas.site ?? 1,
      env: [
        { name: 'API_URL', value: 'http://api:3000' },
        { name: 'SITE_URL', value: `https://${env.domain}` },
        { name: 'APP_URL', value: `https://app.${env.domain}` },
        { name: 'PORTAL_URL', value: `https://portal.${env.domain}` },
        { name: 'CONTACT_EMAIL', value: site.contactEmail ?? '' },
        { name: 'SITE_OPERATOR', value: site.operator ?? 'Event 360' },
        { name: 'SITE_INDEXABLE', value: String(!!site.indexable) },
      ],
      runAsUser: 1000,
      probes: { readinessProbe: { httpGet: { path: '/healthz', port: 'http' }, periodSeconds: 10 } },
      resources: small,
    }),
    service('site', ns, 3000),
  );

  // ── User + Crew web apps: Flutter web builds behind unprivileged nginx ──
  if (env.userWeb) {
    objects.push(
      deployment({
        name: 'user-web',
        ns,
        // Each environment has its own build (API URL is baked into the Flutter web app)
        image: `${config.registry}/event360-user-web:${env.imageTag}${env.userWebTagSuffix ?? ''}`,
        pullPolicy,
        config,
        replicas: 1,
        env: [],
        runAsUser: 101,
        port: 8080,
        probes: { readinessProbe: { httpGet: { path: '/', port: 'http' }, periodSeconds: 10 } },
        resources: { requests: { cpu: '20m', memory: '32Mi' }, limits: { memory: '128Mi' } },
      }),
      service('user-web', ns, 80),
    );
  }

  // ── Live streaming: SRS ingest (RTMP/SRT) on its own LAN IP; transcoders are Jobs started by the API ──
  const st = { ...(config.streaming ?? {}), ...(env.streaming ?? {}) };
  objects.push(
    { apiVersion: 'v1', kind: 'ServiceAccount', metadata: meta('event360-api', ns) },
    {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'Role',
      metadata: meta('event360-api-jobs', ns),
      rules: [
        { apiGroups: ['batch'], resources: ['jobs'], verbs: ['create', 'get', 'list', 'delete'] },
        { apiGroups: [''], resources: ['pods', 'pods/log'], verbs: ['get', 'list'] },
      ],
    },
    {
      apiVersion: 'rbac.authorization.k8s.io/v1',
      kind: 'RoleBinding',
      metadata: meta('event360-api-jobs', ns),
      subjects: [{ kind: 'ServiceAccount', name: 'event360-api', namespace: ns }],
      roleRef: { apiGroup: 'rbac.authorization.k8s.io', kind: 'Role', name: 'event360-api-jobs' },
    },
    {
      apiVersion: 'v1',
      kind: 'ConfigMap',
      metadata: meta('srs-config', ns),
      data: {
        // __HOOK_SECRET__ is filled in from the Secret by the init container
        'srs.conf': [
          'listen 1935;',
          'max_connections 300;',
          'daemon off;',
          'srs_log_tank console;',
          'pid /tmp/srs.pid;',
          'http_api { enabled on; listen 1985; }',
          'srt_server { enabled on; listen 8890; }',
          'vhost __defaultVhost__ {',
          '  srt { enabled on; srt_to_rtmp on; }',
          '  http_hooks {',
          '    enabled on;',
          '    on_publish http://api:3000/v1/streaming/hooks/on_publish?secret=__HOOK_SECRET__;',
          '    on_unpublish http://api:3000/v1/streaming/hooks/on_unpublish?secret=__HOOK_SECRET__;',
          '  }',
          '}',
          '',
        ].join('\n'),
      },
    },
    {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: meta('srs', ns),
      spec: {
        replicas: 1,
        strategy: { type: 'Recreate' },
        selector: { matchLabels: { 'app.kubernetes.io/name': 'srs' } },
        template: {
          metadata: { labels: labels('srs') },
          spec: {
            securityContext: { runAsNonRoot: true, runAsUser: 10001, runAsGroup: 10001 },
            ...avoidNodesAffinity(config),
            volumes: [
              { name: 'tpl', configMap: { name: 'srs-config' } },
              { name: 'conf', emptyDir: {} },
            ],
            initContainers: [
              {
                name: 'config',
                image: 'busybox:1.37',
                command: ['sh', '-c', 'sed "s/__HOOK_SECRET__/$STREAM_HOOK_SECRET/g" /tpl/srs.conf > /conf/srs.conf'],
                env: [{ name: 'STREAM_HOOK_SECRET', valueFrom: { secretKeyRef: { name: SECRET, key: 'STREAM_HOOK_SECRET' } } }],
                volumeMounts: [
                  { name: 'tpl', mountPath: '/tpl' },
                  { name: 'conf', mountPath: '/conf' },
                ],
                securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: ['ALL'] } },
              },
            ],
            containers: [
              {
                name: 'srs',
                image: st.srsImage,
                workingDir: '/usr/local/srs',
                command: ['./objs/srs', '-c', '/conf/srs.conf'],
                ports: [
                  { name: 'rtmp', containerPort: 1935, protocol: 'TCP' },
                  { name: 'srt', containerPort: 8890, protocol: 'UDP' },
                  { name: 'api', containerPort: 1985, protocol: 'TCP' },
                ],
                readinessProbe: { tcpSocket: { port: 'rtmp' }, periodSeconds: 10 },
                volumeMounts: [{ name: 'conf', mountPath: '/conf' }],
                resources: { requests: { cpu: '200m', memory: '128Mi' }, limits: { memory: '1Gi' } },
                securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: ['ALL'] } },
              },
            ],
          },
        },
      },
    },
    {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: meta('srs', ns),
      spec: {
        selector: { 'app.kubernetes.io/name': 'srs' },
        ports: [
          { name: 'rtmp', port: 1935, targetPort: 'rtmp', protocol: 'TCP' },
          { name: 'api', port: 1985, targetPort: 'api', protocol: 'TCP' },
        ],
      },
    },
    {
      // Public ingest: dev and prod share the media IP on different ports (MetalLB allow-shared-ip)
      apiVersion: 'v1',
      kind: 'Service',
      metadata: meta('srs-ingest', ns, {
        annotations: {
          'metallb.universe.tf/loadBalancerIPs': st.ingestIp,
          'metallb.universe.tf/allow-shared-ip': 'event360-ingest',
          'metallb.io/loadBalancerIPs': st.ingestIp,
          'metallb.io/allow-shared-ip': 'event360-ingest',
        },
      }),
      spec: {
        type: 'LoadBalancer',
        externalTrafficPolicy: 'Cluster',
        selector: { 'app.kubernetes.io/name': 'srs' },
        ports: [
          { name: 'rtmp', port: st.rtmpPort, targetPort: 'rtmp', protocol: 'TCP' },
          { name: 'srt', port: st.srtPort, targetPort: 'srt', protocol: 'UDP' },
        ],
      },
    },
    {
      // Encoders connect from anywhere; everything else stays private (see event360-default)
      apiVersion: 'networking.k8s.io/v1',
      kind: 'NetworkPolicy',
      metadata: meta('srs-ingest', ns),
      spec: {
        podSelector: { matchLabels: { 'app.kubernetes.io/name': 'srs' } },
        policyTypes: ['Ingress'],
        ingress: [{ ports: [{ protocol: 'TCP', port: 1935 }, { protocol: 'UDP', port: 8890 }] }],
      },
    },
  );

  // ── Ingress (Traefik; TLS terminated upstream by NPMPlus) ──
  const routes = [
    [`api.${env.domain}`, 'api'],
    [`ws.${env.domain}`, 'realtime'],
    [`portal.${env.domain}`, 'web'],
    ...(env.userWeb ? [[`app.${env.domain}`, 'user-web']] : []),
    ...(site.enabled ? [[env.domain, 'site']] : []),
    ...(site.enabled && site.www ? [[`www.${env.domain}`, 'site']] : []), // the site redirects www → apex
  ];
  objects.push({
    apiVersion: 'networking.k8s.io/v1',
    kind: 'Ingress',
    metadata: meta('event360', ns),
    spec: {
      ingressClassName: 'traefik',
      rules: routes.map(([host, svc]) => ({
        host,
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
