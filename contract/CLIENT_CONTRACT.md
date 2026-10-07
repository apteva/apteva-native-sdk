# Native client contract

Contract version: `1.1`

This is the stable boundary between an Apteva server and native clients. It is
not a UI specification.

## Connection and authentication

1. Accept an absolute HTTPS server URL, adding `https://` when the scheme is
   omitted. Reject credentials in URLs, query/fragment components, non-HTTPS
   schemes, and missing hosts.
2. Resolve all first-party requests below the selected server's `/api/` path.
3. Use the password only for `POST /api/auth/login` and never persist it.
4. After login, read `/api/auth/me`, create one private device key through
   `POST /api/auth/keys`, and persist only the returned key metadata in the
   platform secure store.
5. Use `Authorization: Bearer <device-key>` consistently for REST, SSE,
   app-proxied requests, and protected downloads.
6. Restore by loading the device key and verifying `/api/auth/me` plus
   `/api/projects`. A confirmed `401` invalidates the session. Connection and
   server failures do not delete a previously valid credential.
7. Disconnect by unregistering push, deleting the device key when reachable,
   clearing cookies and secure local credentials, and then clearing app state.

MFA is outside this contract.

## Transport

- JSON uses the server's snake-case wire names and ignores unknown response
  fields for forwards compatibility.
- `401` is unauthenticated; `403` is not authorized; `409` and `412` are state
  conflicts; `429` and `5xx` may be retried with bounded backoff.
- REST uses bounded request/resource timeouts. SSE uses a long-lived streaming
  transport with event IDs, reconnect backoff, and cursor resumption.
- App-native traffic is restricted to `/api/apps/{declaring-app}/...`; callers
  cannot inject an origin, bearer header, or project identity.
- Project identity is supplied by the SDK through the server-defined query or
  host-injected app context, never accepted from an untrusted surface document.

## Compatibility

- Client model decoders tolerate new response fields.
- Breaking field or endpoint changes require a new contract version.
- New optional endpoints and fields may be added within a contract version.
- Shared JSON fixtures should be added for every changed wire shape before an
  SDK release.
- Clients never synthesize plausible business values for missing wire fields.
  Required identity and state fields fail decoding when absent; optional
  presentation fields remain absent.
- A successful empty response, a failed response, and previously loaded stale
  data are distinct states. Clients must not present a failed request as an
  empty success.
- Protected same-origin assets are fetched by the SDK with the same bearer
  credential as REST. Credentials are never forwarded to third-party asset
  origins.
- User-wide unread summaries are scoped against the project conversation list
  before they are presented as a project badge.

## Required SDK domains

- compatibility and health;
- authentication, device keys, users, and projects;
- agents, runtime connections, MCP capabilities, and telemetry;
- dashboard layouts and Inbox artifacts;
- conversations, messages, presence, and user/project/chat SSE;
- installed apps, marketplace, preflight, lifecycle, and native app traffic;
- mobile push configuration, subscription, test, and removal.
