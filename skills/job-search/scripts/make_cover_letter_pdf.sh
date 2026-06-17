#!/bin/bash
#
# make_cover_letter_pdf.sh — render a cover-letter markdown file to a styled one-page PDF.
#
# Usage:
#   make_cover_letter_pdf.sh <input.md> [output.pdf] [--name "..."] [--subtitle "..."]
#
# This script is general-purpose and contains NO personal details. The applicant name must be
# supplied by the caller, either via --name or the $JOB_SEARCH_APPLICANT_NAME env var (source it
# from your private profile, e.g. ~/workspace/jobs/profile.md). The script errors if no name is
# given.
#
# Defaults:
#   output.pdf  -> same dir/basename as input, with .pdf extension
#   --name      -> $JOB_SEARCH_APPLICANT_NAME (required if the flag is omitted)
#   --subtitle  -> "" (letterhead tagline omitted if empty). Use a middle dot "·" as a
#                  separator, NOT a dash, if your house style forbids em/en dashes.
#
# Behavior:
#   - A leading markdown H1 (e.g. "# Cover Letter — ...") is treated as an internal title and
#     dropped from the rendered letter; the body and signature render as a real letter.
#   - Adds a centered letterhead (name + subtitle) above the body.
#   - Margins: 1in left/right, 0.5in top/bottom (0.5in is the practical floor before content
#     hits the page edge). Roomy line spacing (1.55).
#   - Overrides pandoc's default template CSS (max-width:36em + 50px padding), which otherwise
#     stacks on the page margin and looks like ~2in side margins.
#
# Toolchain mirrors the resume repo's _publish: pandoc -> HTML -> headless Chrome -> PDF.
# Requires: pandoc, and google-chrome-stable (or chromium / google-chrome).

set -euo pipefail

# No personal defaults here — name comes from --name or the env var (see header). Keep it that way.
NAME="${JOB_SEARCH_APPLICANT_NAME:-}"
SUBTITLE=""
INPUT=""
OUTPUT=""

# --- arg parsing (positionals + flags, any order) ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)     NAME="$2";     shift 2 ;;
    --subtitle) SUBTITLE="$2"; shift 2 ;;
    -h|--help)  grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)
      if [[ -z "$INPUT" ]]; then INPUT="$1"
      elif [[ -z "$OUTPUT" ]]; then OUTPUT="$1"
      else echo "Unexpected arg: $1" >&2; exit 1
      fi
      shift ;;
  esac
done

if [[ -z "$INPUT" || ! -f "$INPUT" ]]; then
  echo "Error: input markdown file not found. Usage: $0 <input.md> [output.pdf] [--name ..] [--subtitle ..]" >&2
  exit 1
fi
[[ -z "$OUTPUT" ]] && OUTPUT="${INPUT%.md}.pdf"

if [[ -z "$NAME" ]]; then
  echo "Error: applicant name required. Pass --name \"...\" or set \$JOB_SEARCH_APPLICANT_NAME" >&2
  echo "       (source it from your private profile, e.g. ~/workspace/jobs/profile.md)." >&2
  exit 1
fi

# --- locate a Chrome/Chromium binary ---
CHROME=""
for c in google-chrome-stable google-chrome chromium chromium-browser; do
  if command -v "$c" >/dev/null 2>&1; then CHROME="$c"; break; fi
done
if [[ -z "$CHROME" ]]; then echo "Error: no Chrome/Chromium binary found." >&2; exit 1; fi
command -v pandoc >/dev/null 2>&1 || { echo "Error: pandoc not found." >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- drop a leading H1 title line (internal doc title), keep the rest verbatim ---
awk 'NR==1 && /^# / {next} {print}' "$INPUT" > "$TMP/body.md"

# --- styling: true 1in side / 0.5in top-bottom margins, roomy spacing, pandoc overrides ---
cat > "$TMP/header.html" <<'CSS'
<style>
  @page { margin: 0.5in 1in; }
  html { font-size: 11pt; }
  body {
    margin: 0 !important;
    padding: 0 !important;
    max-width: none !important;
    font-family: Georgia, "Times New Roman", serif;
    font-size: 11pt;
    line-height: 1.55;
    color: #1a1a1a;
  }
  .letterhead {
    text-align: center;
    border-bottom: 1px solid #ccc;
    padding-bottom: 9px;
    margin-bottom: 22px;
  }
  .letterhead .name { font-size: 18pt; font-weight: bold; letter-spacing: 0.5px; }
  .letterhead .sub  { font-size: 10pt; color: #555; margin-top: 4px; }
  p { margin: 0 0 14px 0; text-align: left; }
</style>
CSS

# --- letterhead (written with literal chars; HTML-escape & in the values) ---
esc() { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }
{
  printf '<div class="letterhead">\n'
  printf '  <div class="name">%s</div>\n' "$(esc "$NAME")"
  [[ -n "$SUBTITLE" ]] && printf '  <div class="sub">%s</div>\n' "$(esc "$SUBTITLE")"
  printf '</div>\n'
} > "$TMP/before.html"

pandoc "$TMP/body.md" -o "$TMP/out.html" -t html5 -f markdown+smart --standalone \
  --include-in-header="$TMP/header.html" \
  --include-before-body="$TMP/before.html" \
  --variable="pagetitle:Cover Letter :: ${NAME}"

"$CHROME" --headless --disable-gpu --no-pdf-header-footer \
  --print-to-pdf="$OUTPUT" "$TMP/out.html" >/dev/null 2>&1

echo "Wrote: $OUTPUT"
if command -v pdfinfo >/dev/null 2>&1; then
  echo "Pages: $(pdfinfo "$OUTPUT" 2>/dev/null | awk '/^Pages/{print $2}')"
fi
