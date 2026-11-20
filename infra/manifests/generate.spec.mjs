// Run with: node --test infra/manifests/
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { buildManifests, render } from './generate.mjs';

const config = JSON.parse(readFileSync(new URL('./envs.json', import.meta.url), 'utf8'));

for (const envName of Object.keys(config.environments)) {
  const env = config.environments[envName];
  const objs = buildManifests(envName, config);
  const byKind = (k) => objs.filter((o) => o.kind === k);

  test(`${envName}: every object lives in ${env.namespace}`, () => {
    for (const o of objs) assert.equal(o.metadata.namespace, env.namespace, `${o.kind}/${o.metadata.name}`);
  });

  test(`${envName}: does not manage the Namespace or any Secret`, () => {
    assert.equal(byKind('Namespace').length, 0);
    assert.equal(byKind('Secret').length, 0);
  });

  test(`${envName}: expected workloads`, () => {
    const expected = ['api', 'realtime', ...(env.site?.enabled ? ['site'] : []), 'srs', 'web', 'worker', ...(env.userWeb ? ['user-web'] : [])].sort();
    assert.deepEqual(byKind('Deployment').map((d) => d.metadata.name).sort(), expected);
    assert.deepEqual(byKind('StatefulSet').map((d) => d.metadata.name), ['redis']);
  });

  test(`${envName}: Traefik ingress with the right hosts`, () => {
    const [ing] = byKind('Ingress');
    assert.equal(ing.spec.ingressClassName, 'traefik');
    assert.deepEqual(
      ing.spec.rules.map((r) => r.host),
      [
        ...['api', 'ws', 'portal', ...(env.userWeb ? ['app'] : [])].map((h) => `${h}.${env.domain}`),
        ...(env.site?.enabled ? [env.domain] : []),
        ...(env.site?.enabled && env.site?.www ? [`www.${env.domain}`] : []),
      ],
    );
    const site = byKind('Deployment').find((d) => d.metadata.name === 'site');
    if (env.site?.enabled) {
      const e = Object.fromEntries(site.spec.template.spec.containers[0].env.map((x) => [x.name, x.value]));
      assert.equal(e.SITE_URL, `https://${env.domain}`);
      assert.equal(e.SITE_INDEXABLE, envName === 'prod' ? 'true' : 'false'); // only prod is indexed by search engines
    } else assert.equal(site, undefined);
  });

  test(`${envName}: workloads avoid avoidNodes; storage workloads also avoid storageAvoidNodes`, () => {
    const avoided = (w) =>
      w.spec.template.spec.affinity?.nodeAffinity?.requiredDuringSchedulingIgnoredDuringExecution?.nodeSelectorTerms?.[0]
        ?.matchExpressions?.[0]?.values ?? [];
    for (const w of byKind('Deployment')) assert.deepEqual(avoided(w), config.avoidNodes ?? [], w.metadata.name);
    for (const w of byKind('StatefulSet')) {
      const expected = [...new Set([...(config.avoidNodes ?? []), ...(config.storageAvoidNodes ?? [])])];
      assert.deepEqual(avoided(w), expected, w.metadata.name);
    }
  });

  test(`${envName}: API runs migrations before starting`, () => {
    const api = byKind('Deployment').find((d) => d.metadata.name === 'api');
    assert.match(api.spec.template.spec.initContainers[0].command.join(' '), /prisma migrate deploy && node dist\/seed\.js/);
  });

  test(`${envName}: no secret values leak into the manifest`, () => {
    const text = render(envName, config);
    assert.doesNotMatch(text, /postgresql:\/\//);
    assert.doesNotMatch(text, /JWT_(ACCESS|REFRESH)_SECRET/);
    for (const v of ['PostgreSQL_Password', 'SeaweedFS_SecretKey', 'Portainer_Password']) {
      const secret = process.env[v];
      if (secret) assert.ok(!text.includes(secret), `${v} found in manifest`);
    }
  });

  test(`${envName}: streaming ingest on the media IP with per-env ports; API may start Jobs`, () => {
    const st = { ...config.streaming, ...env.streaming };
    const lb = byKind('Service').find((x) => x.metadata.name === 'srs-ingest');
    assert.equal(lb.spec.type, 'LoadBalancer');
    assert.equal(lb.metadata.annotations['metallb.universe.tf/loadBalancerIPs'], st.ingestIp);
    assert.deepEqual(lb.spec.ports.map((p) => [p.port, p.protocol]), [[st.rtmpPort, 'TCP'], [st.srtPort, 'UDP']]);
    const role = byKind('Role').find((x) => x.metadata.name === 'event360-api-jobs');
    assert.deepEqual(role.rules[0], { apiGroups: ['batch'], resources: ['jobs'], verbs: ['create', 'get', 'list', 'delete'] });
    const api = byKind('Deployment').find((d) => d.metadata.name === 'api');
    assert.equal(api.spec.template.spec.serviceAccountName, 'event360-api');
    const e = Object.fromEntries(api.spec.template.spec.containers[0].env.map((x) => [x.name, x.value]));
    assert.equal(e.STREAM_RTMP_URL, `rtmp://${st.ingestHost}:${st.rtmpPort}/live`);
    const srsConf = byKind('ConfigMap').find((x) => x.metadata.name === 'srs-config').data['srs.conf'];
    assert.match(srsConf, /secret=__HOOK_SECRET__/); // real secret only injected at runtime
  });

  test(`${envName}: the test wallet (Mock pay) is only on dev`, () => {
    for (const name of ['api', 'worker', 'realtime']) {
      const d = byKind('Deployment').find((x) => x.metadata.name === name);
      const e = Object.fromEntries(d.spec.template.spec.containers[0].env.map((x) => [x.name, x.value]));
      assert.equal(e.PAYMENTS_MOCK, envName === 'dev' ? 'true' : 'false');
    }
  });
}
