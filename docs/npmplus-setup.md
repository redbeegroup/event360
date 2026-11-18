# Running Event 360 behind NPMPlus

```
Internet ──HTTPS──▶ NPMPlus (TLS, Let's Encrypt) ──HTTP──▶ Traefik 172.16.16.180:80 (k8s) ──▶ api / ws / portal
          ──RTMP/SRT──▶ NPMPlus "Streams" (TCP/UDP) ──▶ srs-ingest LoadBalancer/NodePort   (Phase 5b)
```

## 1. Proxy hosts (one per public hostname)

Forward each host to **`http://172.16.16.180:80`** (the Traefik LoadBalancer).
The ingress routes by `Host` header, so NPMPlus must pass the original host through (it does by default).

| Host | Websockets | Notes |
|---|---|---|
| `api.event360.corexlab.net` | off | Payment provider webhooks arrive here |
| `ws.event360.corexlab.net` | **on** | Socket.IO: live counts, chat, Q&A |
| `portal.event360.corexlab.net` | off | Next.js admin / organizer portal |
| `media.event360.corexlab.net` | off | HLS playback (Phase 5b). Disable buffering for low latency |
| `watch.event360.corexlab.net` | off | Web player (Phase 5b) |

Repeat for the `.dev.` hostnames (`api.dev.`, `ws.dev.`, `portal.dev.event360.corexlab.net`). See certificates below.

## 2. Certificates

Use a DNS-challenge wildcard certificate in NPMPlus. A wildcard covers **one** label only:

- `*.event360.corexlab.net` → prod hosts
- `*.dev.event360.corexlab.net` → needs its own wildcard cert

## 3. Real client IP (required)

Rate limits (OTP, checkout) and audit logs need the real client IP, not the NPMPlus IP.

- NPMPlus sends `X-Forwarded-For` / `X-Real-IP` by default.
- Traefik must trust NPMPlus's forwarded headers. Add to Traefik's `web` entrypoint (Traefik Helm values):
  ```yaml
  additionalArguments:
    - "--entryPoints.web.forwardedHeaders.trustedIPs=<NPMPlus LAN IP>/32"
  ```
  Without this, Traefik replaces `X-Forwarded-For` with the NPMPlus IP, and per-IP rate limits throttle all users together.
- The API trusts 2 proxy hops (`TRUST_PROXY: "2"` in `values.yaml`).
- **Firewall 172.16.16.180 so only NPMPlus can reach it.** Otherwise clients could spoof `X-Forwarded-For`.

## 4. Per-host custom Nginx config

For `ws.` (Advanced tab). Traefik itself has no idle timeout for WebSockets:
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
