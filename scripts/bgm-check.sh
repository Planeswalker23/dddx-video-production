#!/usr/bin/env bash
# bgm-check.sh - vet background-music candidates before they go into a cut.
#
# Prints duration, integrated loudness (LUFS), true peak (dBTP) and loudness range (LRA)
# for every file, plus the gain needed to land the track in the bed range under a
# -14 LUFS voice-over (BGM sits 18-22 dB below the voice: aim for -32 to -36 LUFS).
#
# Usage: bash bgm-check.sh <file...> [--need <seconds>]
#   --need 62    flag anything shorter than the film (62 s here)
# Exit: 0 = all usable, 1 = at least one file is too short / hot, 2 = bad usage
set -u

NEED=0
FILES=()

usage() {
  cat <<'EOF'
Usage: bash bgm-check.sh <file...> [--need <seconds>]

  --need <s>   film length; anything shorter gets flagged. Default 0 (no check).

Exit: 0 = all usable, 1 = a file is too short or peaking, 2 = bad usage.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --need|-Need) shift; NEED="${1:-0}" ;;
    -h|--help|-Help) usage; exit 0 ;;
    -*) printf 'unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *) FILES+=("$1") ;;
  esac
  shift
done

if [ "${#FILES[@]}" -eq 0 ]; then usage >&2; exit 2; fi
case "$NEED" in ''|*[!0-9]*) printf 'invalid --need: %s\n' "$NEED" >&2; exit 2 ;; esac
command -v ffmpeg  >/dev/null 2>&1 || { echo "ffmpeg not found in PATH"  >&2; exit 1; }
command -v ffprobe >/dev/null 2>&1 || { echo "ffprobe not found in PATH" >&2; exit 1; }

BAD=0
printf '%-34s %8s %9s %9s %6s  %s\n' 'file' 'length' 'LUFS' 'true peak' 'LRA' 'note'
printf '%s\n' '----------------------------------------------------------------------------------------'

for f in "${FILES[@]}"; do
  if [ ! -f "$f" ]; then
    printf '%-34s %8s\n' "$(basename "$f")" 'MISSING'
    BAD=1
    continue
  fi

  dur="$(ffprobe -v error -show_entries format=duration -of 'csv=p=0' "$f" 2>/dev/null | head -n 1)"
  case "$dur" in ''|N/A) dur=0 ;; esac
  # ebur128 prints a final summary block; the last "I:" / "LRA:" / "Peak:" lines are it.
  stats="$(ffmpeg -hide_banner -nostats -i "$f" -af ebur128=peak=true -f null - 2>&1)"
  lufs="$(printf '%s\n' "$stats" | grep -E '^[[:space:]]+I:'    | tail -n 1 | sed -E 's/.*I:[[:space:]]*(-?[0-9.]+).*/\1/')"
  lra="$( printf '%s\n' "$stats" | grep -E '^[[:space:]]+LRA:'  | tail -n 1 | sed -E 's/.*LRA:[[:space:]]*(-?[0-9.]+).*/\1/')"
  peak="$(printf '%s\n' "$stats" | grep -E '^[[:space:]]+Peak:' | tail -n 1 | sed -E 's/.*Peak:[[:space:]]*(-?[0-9.]+).*/\1/')"
  [ -z "$lufs" ] && lufs='?'
  [ -z "$lra" ]  && lra='?'
  [ -z "$peak" ] && peak='?'

  length="$(awk -v s="$dur" 'BEGIN{ s=s+0; if (s<=0) {print "?"; exit} printf "%d:%02d", int(s/60), int(s)%60 }')"

  note=''
  if [ "$NEED" -gt 0 ]; then
    ok="$(awk -v s="$dur" -v n="$NEED" 'BEGIN{ print (s + 0 >= n * 1.2) ? 1 : 0 }')"
    if [ "$ok" = 0 ]; then
      note="SHORT for ${NEED}s film (want >= $(awk -v n="$NEED" 'BEGIN{printf "%.0f", n*1.2}')s)"
      BAD=1
    fi
  fi

  # Gain to reach the bed range: -34 LUFS midpoint of -32..-36.
  if [ "$lufs" != '?' ]; then
    gain="$(awk -v i="$lufs" 'BEGIN{ printf "%+.1f", -34 - i }')"
    note="${note:+$note; }bed gain ${gain} dB -> -34 LUFS"
    hot="$(awk -v i="$lufs" 'BEGIN{ print (i > -20) ? 1 : 0 }')"
    [ "$hot" = 1 ] && note="$note; HOT (already loud, big cut needed)"
  fi
  if [ "$peak" != '?' ]; then
    clip="$(awk -v p="$peak" 'BEGIN{ print (p > -1.0) ? 1 : 0 }')"
    if [ "$clip" = 1 ]; then note="$note; PEAK near 0 dBFS"; BAD=1; fi
  fi
  if [ "$lra" != '?' ]; then
    wide="$(awk -v l="$lra" 'BEGIN{ print (l > 12) ? 1 : 0 }')"
    [ "$wide" = 1 ] && note="$note; wide dynamic range (LRA>12) - rides up and down under VO"
  fi

  printf '%-34s %8s %9s %9s %6s  %s\n' "$(basename "$f")" "$length" "${lufs}" "${peak}" "$lra" "$note"
done

printf '\n'
printf 'Read it like this:\n'
printf '  Voice-over sits at about -14 LUFS. BGM should sit 18-22 dB below it,\n'
printf '  i.e. around -32 to -36 LUFS in the mix - apply the "bed gain" above, then fine-tune by ear.\n'
printf '  A track already above -20 LUFS is a loud master: duck it hard or pick another.\n'
if [ "$BAD" = 1 ]; then exit 1; fi
exit 0
