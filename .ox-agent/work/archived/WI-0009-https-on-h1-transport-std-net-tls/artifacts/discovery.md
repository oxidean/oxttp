# WI-0009 discovery

oxl 0.23.2 `std/net/tls`: `Config`, `Verifier`, `dial*`/`client`.
H1 already non-suspending-dials TCP — wrap with `tls.client`.
Parks: #221 mTLS, #222 CONNECT, #224 TLS1.2. IN-0005=B for verify=no.
