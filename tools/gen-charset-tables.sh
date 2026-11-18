#!/bin/sh
# Writes src/charset/tables.blsp: the high half of each single-byte coding, from iconv, so the
# tables are the platform's and not anyone's typing. A byte iconv calls undefined maps to itself,
# which keeps every byte round-tripping. Rerun with: sh tools/gen-charset-tables.sh
set -eu
out=src/charset/tables.blsp

high_codes() {
  byte=128
  while [ "$byte" -lt 256 ]; do
    code=$(printf "\\$(printf %o "$byte")" | iconv -f "$1" -t UTF-32BE 2>/dev/null \
      | od -An -tu1 | gawk '{ if (NF == 4) print $2 * 65536 + $3 * 256 + $4 }')
    printf ' %s' "${code:-$byte}"
    byte=$((byte + 1))
  done
}

row() { # key label iconv-name names common-letters
  printf '   {:coding %s\n    :label "%s"\n    :names [%s]\n    :common "%s"\n    :high [' \
    "$1" "$2" "$4" "$5"
  high_codes "$3" | sed 's/^ //'
  printf ']}\n'
}

{
  cat <<'HEADER'
(defmodule charset/tables
  "The single-byte codings, as data: one row per coding, generated from iconv by
tools/gen-charset-tables.sh, so adding a coding is adding a row there. `:high` is what bytes
128 to 255 mean, `:names` what people call it, and `:common` the letters a text in it is
mostly made of, which is how `charset/detect` recognises a script (a coding with none is
never guessed, only named).")

(def *single-byte*
  [
HEADER
  row :latin-1 ISO-8859-1 ISO-8859-1 '"iso-8859-1" "iso8859-1" "iso_8859-1" "latin1" "latin-1" "l1"' ''
  row :latin-9 ISO-8859-15 ISO-8859-15 '"iso-8859-15" "iso8859-15" "latin9" "latin-9"' ''
  row :windows-1252 windows-1252 CP1252 '"windows-1252" "cp1252" "x-cp1252"' ''
  row :iso-8859-2 ISO-8859-2 ISO-8859-2 '"iso-8859-2" "iso8859-2" "latin2" "latin-2" "l2"' ''
  row :windows-1250 windows-1250 CP1250 '"windows-1250" "cp1250" "x-cp1250"' ''
  row :windows-1254 windows-1254 CP1254 '"windows-1254" "cp1254" "x-cp1254"' ''
  row :windows-1251 windows-1251 CP1251 '"windows-1251" "cp1251" "x-cp1251"' 'оеаинтсрвл'
  row :koi8-r KOI8-R KOI8-R '"koi8-r" "koi8r" "koi8"' 'оеаинтсрвл'
  row :koi8-u KOI8-U KOI8-U '"koi8-u" "koi8u"' ''
  row :iso-8859-5 ISO-8859-5 ISO-8859-5 '"iso-8859-5" "iso8859-5" "cyrillic"' ''
  row :windows-1253 windows-1253 CP1253 '"windows-1253" "cp1253" "x-cp1253"' 'αοιετνσρπυ'
  row :iso-8859-7 ISO-8859-7 ISO-8859-7 '"iso-8859-7" "iso8859-7" "greek"' ''
  row :windows-1255 windows-1255 CP1255 '"windows-1255" "cp1255" "x-cp1255"' 'יוהלאמרתבנ'
  row :windows-1256 windows-1256 CP1256 '"windows-1256" "cp1256" "x-cp1256"' 'اليمونرتبة'
  printf '   ])\n'
} > "$out"
