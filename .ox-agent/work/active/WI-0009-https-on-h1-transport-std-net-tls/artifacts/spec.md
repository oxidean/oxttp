# WI-0009 spec — HTTPS on H1

## Acceptance

1. `https://` URLs round-trip via dial_h1 + tls.client.
2. `--verify=no` uses AcceptAll Verifier; default uses system roots.
3. PEM verify path loads into x509.Roots.
4. `--cert`/`--ssl`<1.3 still deferred with oxl issue citations.
5. Redirect http→https works; ADR-0026 supersedes ADR-0001.
6. Unit tests cover https://example.com and verify=no.
