# ADR-0057 — OAuth bearer overrides Authorization; TUI edits config and exposes Forget

- Status: accepted
- Date: 2026-11-28
- Work item: WI-0022 (M4f OAuth2 authorization flow)

## Context

Upstream builds the OAuth bearer header after user headers, so OAuth replaces
an explicit `Authorization` row for that request. oxttp's S10 planner made
caller-supplied Authorization rows win for every auth type. Upstream also
has an editable OAuth Auth form and a **Forget OAuth token** palette command;
there is no separate working "OAuth sign-in" command — normal send performs
sign-in. oxttp currently renders Auth read-only and has a degraded
`OAuth sign-in` palette row.

## Decision

1. For `auth.type: oauth2`, token acquisition happens after planning and the
   resulting `Authorization: Bearer <access-token>` replaces any explicit
   enabled Authorization row immediately before transport send. Do not alter
   Basic/Bearer precedence in this WI; record that broader mismatch separately.
2. Implement the OAuth portion of the Auth editor: auth-type selection enough
   to choose OAuth2, grant selector, conditional auth/redirect fields,
   token/client/scope inputs, client-auth selector, status text, and normal
   draft/save round trip. Runtime tokens are never editor state.
3. Replace the degraded `OAuth sign-in` palette row with upstream's
   **Forget OAuth token** command for OAuth requests. Sending remains the
   sign-in path. Forget clears the session token through the same resolved
   cache key and reports that provider consent is not revoked.
4. OAuth curl/grpccurl export must refuse with the upstream safe error when
   export implementation reaches this branch; do not export generated tokens.

## Consequences

- OAuth wire behavior matches upstream on the auth-header collision that
  matters here, while Basic/Bearer stay on their existing behavior pending a
  focused correction.
- TUI users can configure, sign in, reuse/refresh, and forget OAuth without
  hand-editing YAML. Memory-only persistence remains governed by ADR-0054.
