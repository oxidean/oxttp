# 0014 — h1 transport advertises only decodable content-encodings

Status: accepted (2026-11-17, WI-0004 brainstorm)

xh sends `accept-encoding: gzip, deflate, br, zstd` and decodes all
four internally (corpus §4.6, src/decoder.rs). oxl std ships decoders
for gzip, zlib, and raw flate only — no brotli, no zstd
(`std/compress`). Advertising br/zstd anyway would let a server
legally answer with bytes oxttp cannot decode.

The h1 transport therefore injects `Accept-Encoding: gzip, deflate`
when the caller supplied none — a recorded corpus deviation, not a
silent one. Decoding honors the xh alias set (`gzip`, `x-gzip`,
`deflate` = zlib-then-raw-flate fallback, `x-compress`); any other
Content-Encoding value is an explicit `unsupported content-encoding`
error rather than passing compressed bytes through.

Consequence: when std (or a future dependency) gains br/zstd
decoders, restoring the corpus-faithful four-token advertisement is
a one-line change plus tests; the deviation lives in exactly one
place — the injected default header — and caller-supplied
`Accept-Encoding` always wins.
