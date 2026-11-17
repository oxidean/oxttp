# xh REQUEST_ITEM grammar — source-verified reference

Pinned source: /tmp/oxttp-corpus/xh-src @ 8b21cc07 (xh 0.26.3),
src/request_items.rs L39-180, src/utils.rs unescape L11-37.
Corpus docs/corpus/corpus-xh.md section 3 is faithful; this note records
the exact algorithm plus details the table leaves implicit.

## split() - separator scan

SEPS = ["==@", "=@", ":=@", ":@", "==", ":=", "=", "@", ":"]

- Walk char positions left-to-right. At each position, try every sep in
  SEPS order (longest-first); first position where any sep matches wins.
- On backslash: consume the next char unconditionally - special or not,
  it can never start a separator. A trailing backslash just ends the
  scan.
- Result: (raw_key, sep, value) where raw_key/value are raw slices
  (escapes intact).

## Variant mapping (after split)

key = unescape(raw_key, "=@:;\\"), value = unescape(value, "=@:;\\").

| sep | variant | key field used |
|---|---|---|
| == | UrlParam | unescaped key |
| ==@ | UrlParamFromFile | key |
| = | DataField{key, raw_key, value} | both kept |
| =@ | DataFieldFromFile{key, raw_key, value} | both kept |
| := | JsonField(raw_key, json_value) | raw_key (nested-JSON paths); parse error gives Invalid value for '[REQUEST_ITEM]...': {item:?} {err} |
| :=@ | JsonFieldFromFile(raw_key, value) | raw_key |
| : empty value | HttpHeaderToUnset | key |
| : | HttpHeader | key |
| :@ | HttpHeaderFromFile | key |
| @ | FormFile{key, file_name, file_type, file_name_header} | key; parse_part_params runs on the unescaped value |

## key; empty header - checked AFTER split fails

else if strip_suffix(';') gives HttpHeader(header.to_owned(), "").
Source quirks, both deliberate parity targets:

- fires only when the sep scan found nothing (a=b; gives DataField b;,
  not a header);
- the ; need not be unescaped - foo\; still matches ("technically too
  permissive" per upstream code comment);
- the key is NOT unescaped here (foo\; gives header name foo\), unlike
  every sep-match path.

## unescape(text, special="=@:;\\")

- backslash + special char gives literal char (in key AND value).
- backslash + non-special keeps both chars literally (f\o\o, \ba\r).
- trailing backslash stays literal.
- nested-JSON path parsing (S6) reuses this fn with [ ] added - keep
  unescape parameterized by the special set.

## parse_part_params(text) - key@file;type=T;filename=F

- delims [";type=", ";filename="]; repeatedly split on the rightmost
  occurrence of any remaining delim; each delim consumed once
  (delims.retain(!= found)); text = pre each round.
- ;type= gives file_type; ;filename= gives file_name_header (the
  multipart Content-Disposition filename, not the disk path).
- leftovers stay in value: f@x;type=a;type=b gives file "x;type=a",
  type "b".
- empty key on @ is legal: @file gives FormFile{key:""} - whole-body
  file upstream (Body::File mapping is S6, not S2).

## Error shape

No sep and no trailing ';' gives clap InvalidValue:
Invalid value for '[REQUEST_ITEM]...': {request_item:?} (Rust {:?} is
the double-quoted escaped string). The parse result must carry enough
to emit this verbatim at the CLI layer.
