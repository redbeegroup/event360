# Running Event 360 behind NPMPlus

```
Internet ──HTTPS──▶ NPMPlus (TLS, Let's Encrypt) ──HTTP──▶ ingress-nginx (k8s) ──▶ api / ws / portal
          ──RTMP/SRT──▶ NPMPlus "Streams" (TCP/UDP) ──▶ srs-ingest LoadBalancer/NodePort   (Phase 5b)
```

## 1. Proxy hosts (one per public hostname)

Forward each host to the ingress-nginx Service (NodePort or LoadBalancer IP), scheme `http`.
The ingress routes by `Host` header, so NPMPlus must pass the original host through (it does by default).

| Host | Websockets | Notes |
|---|---|---|
| `api.event360.corexlab.net` | off | Payment provider webhooks arrive here |
| `ws.event360.corexlab.net` | **on** | Socket.IO: live counts, chat, Q&A |
| `portal.event360.corexlab.net` | off | Next.js admin / organizer portal |
| `media.event360.corexlab.net` | off | HLS playback (Phase 5b). Disable buffering for low latency |
| `watch.event360.corexlab.net` | off | Web player (Phase 5b) |

Repeat with `.staging.` / `.dev.` hostnames (see certificates below).

## 2. Certificates

Use a DNS-challenge wildcard certificate in NPMPlus. A wildcard covers **one** label only:

- `*.event360.corexlab.net` → prod hosts
- `*.staging.event360.corexlab.net` and `*.dev.event360.corexlab.net` → need their own wildcard certs

## 3. Real client IP (required)

Rate limits (OTP, checkout) and audit logs need the real client IP, not the NPMPlus IP.

- NPMPlus sends `X-Forwarded-For` / `X-Real-IP` by default.
- ingress-nginx controller ConfigMap (cluster-wide):
  ```yaml
  use-forwarded-headers: "true"
  proxy-real-ip-cidr: "<NPMPlus IP>/32"
  ```
- The API trusts 2 proxy hops (`TRUST_PROXY: "2"` in `values.yaml`).
- **Firewall the ingress so only NPMPlus can reach it.** Otherwise clients could spoof `X-Forwarded-For`.

## 4. Per-host custom Nginx config

For `ws.` (Advanced tab):
```nginx
proxy_read_timeout 3600s;
proxy_send_timeout 3600s;
```
For `api.` and `portal.`:
```nginx
client_max_body_size 20m;
```
Video uploads (Phase 5b) go straight to SeaweedFS with presigned URLs. If SeaweedFS's S3 endpoint is
published through NPMPlus, give that host `client_max_body_size 0;` and `proxy_request_buffering off;`.

For `media.` (HLS):
```nginx
proxy_buffering off;
```
Caching is done by `playback-edge` in the cluster, so don't cache in NPMPlus. Access tokens are in the
URL, and caching there could serve content without checking them.

## 5. Live ingest (Phase 5b)

Use NPMPlus **Streams** for:
- TCP 1935 → srs-ingest (RTMP)
- UDP 10080 → srs-ingest (SRT)

Alternatively expose srs-ingest's LoadBalancer IP directly on `ingest.event360.corexlab.net`.

## 6. Things NPMPlus does not change

- **Outbound traffic:** calls from the cluster to payment providers don't go through NPMPlus. The fixed IP that
  providers whitelist is the **cluster's egress IP**.
- **Single point of failure:** if NPMPlus goes down, the whole platform goes offline. Before launch, plan a
  standby instance or monitor it closely.
