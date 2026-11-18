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
    const expected = ['api', 'realtime', 'web', 'worker', ...(env.userWeb ? ['user-web'] : [])].sort();
    assert.deepEqual(byKind('Deployment').map((d) => d.metadata.name).sort(), expected);
    assert.deepEqual(byKind('StatefulSet').map((d) => d.metadata.name), ['redis']);
  });

  test(`${envName}: Traefik ingress with the right hosts`, () => {
    const [ing] = byKind('Ingress');
    assert.equal(ing.spec.ingressClassName, 'traefik');
    assert.deepEqual(
      ing.spec.rules.map((r) => r.host),
      ['api', 'ws', 'portal', ...(env.userWeb ? ['app'] : [])].map((h) => `${h}.${env.domain}`),
    );
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
}
