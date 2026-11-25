#!/usr/bin/env bash
# Detect the video-production tool chain (Voicebox / ChatCut Desktop / Node) on macOS and Linux,
# report what is missing, and auto-launch what is installed but not running.
#
# This is the POSIX counterpart of check-tools.ps1. It also self-dispatches: run it from
# WSL or Git Bash on Windows and it hands over to check-tools.ps1 instead.
#
# Usage: bash scripts/check-tools.sh [--no-launch] [--port 17493]
#        -NoLaunch / -Port 17493 are accepted too (so one call site works on every OS).
# Exit: 0 = all ready, 2 = blocked

set -u

NO_LAUNCH=0
PORT=17493
VB_WAIT=45
CC_WAIT=25

usage() {
  cat <<'EOF'
Usage: bash check-tools.sh [--no-launch] [--port 17493]

  --no-launch     Only report state, never start an app (troubleshooting).
  --port <n>      Voicebox API port, default 17493.

Exit: 0 = all ready, 2 = blocked.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --no-launch|-NoLaunch|-nolaunch) NO_LAUNCH=1 ;;
    --port|-Port) shift; PORT="${1:-17493}" ;;
    -h|--help|-Help) usage; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

case "$PORT" in
  ''|*[!0-9]*) printf 'invalid --port: %s\n' "$PORT" >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
UNAME_S="$(uname -s 2>/dev/null || echo unknown)"

# ---------------------------------------------------------------- platform dispatch
# On Windows the POSIX shell is only an entry point; real detection lives in PowerShell.
if printf '%s' "$UNAME_S" | grep -qiE '^(MINGW|MSYS|CYGWIN)'; then
  PS1="$SCRIPT_DIR/check-tools.ps1"
  if command -v powershell.exe >/dev/null 2>&1; then
    if [ "$NO_LAUNCH" = 1 ]; then
      exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS1" -NoLaunch -Port "$PORT"
    fi
    exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS1" -Port "$PORT"
  fi
  echo "Windows detected but powershell.exe is not reachable; run check-tools.ps1 directly." >&2
  exit 1
fi

if [ "$UNAME_S" != "Darwin" ] && grep -qi microsoft /proc/version 2>/dev/null; then
  # WSL: Windows-side apps are what matter here, so delegate to PowerShell.
  if command -v powershell.exe >/dev/null 2>&1; then
    if command -v wslpath >/dev/null 2>&1; then
      PS1_WIN="$(wslpath -w "$SCRIPT_DIR/check-tools.ps1" 2>/dev/null || echo "$SCRIPT_DIR/check-tools.ps1")"
    else
      PS1_WIN="$SCRIPT_DIR/check-tools.ps1"
    fi
    if [ "$NO_LAUNCH" = 1 ]; then
      exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS1_WIN" -NoLaunch -Port "$PORT"
    fi
    exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PS1_WIN" -Port "$PORT"
  fi
fi

case "$UNAME_S" in
  Darwin) PLATFORM=macos ;;
  Linux)  PLATFORM=linux ;;
  *)      PLATFORM=other ;;
esac

# ---------------------------------------------------------------- helpers

# TCP reachability: port open == API ready. More reliable than hunting for a pid.
tcp_open() {
  host="$1"
  port="$2"
  if command -v nc >/dev/null 2>&1; then
    nc -z -G 1 -w 2 "$host" "$port" >/dev/null 2>&1 && return 0
    nc -z -w 1 "$host" "$port" >/dev/null 2>&1 && return 0
    return 1
  fi
  ( exec 3<>"/dev/tcp/$host/$port" ) >/dev/null 2>&1 || return 1
  exec 3>&- 3<&- 2>/dev/null
  return 0
}

# First existing path wins; then Spotlight (macOS) as a last resort.
find_app() {
  app_name="$1"
  shift
  for p in "$@"; do
    if [ -e "$p" ]; then printf '%s\n' "$p"; return 0; fi
  done
  if command -v mdfind >/dev/null 2>&1; then
    hit="$(mdfind -name "$app_name" 2>/dev/null | grep -E "/$app_name/?$" | head -n 1)"
    if [ -n "$hit" ]; then printf '%s\n' "$hit"; return 0; fi
  fi
  return 1
}

# Launch a .app (or an executable) without stealing focus if possible.
launch_app() {
  target="$1"
  if [ "$PLATFORM" = macos ]; then
    open "$target" >/dev/null 2>&1 || return 1
  else
    if [ -x "$target" ]; then
      nohup "$target" >/dev/null 2>&1 &
    else
      return 1
    fi
  fi
  return 0
}

cc_running() {
  pgrep -f 'ChatCut\.app/Contents/MacOS' >/dev/null 2>&1 && return 0
  pgrep -x 'ChatCut' >/dev/null 2>&1 && return 0
  pgrep -f '/ChatCut($| )' >/dev/null 2>&1 && return 0
  return 1
}

# ---------------------------------------------------------------- install URLs
case "$PLATFORM" in
  macos)
    VB_URL='https://voicebox.sh/download?platform=macos'
    CC_URL='curl -fsSL https://chatcut.io/install.sh | sh'
    ;;
  linux)
    VB_URL='https://voicebox.sh/download'
    CC_URL='(ChatCut Desktop has no Linux build - stage 4 must run on macOS or Windows)'
    ;;
  *)
    VB_URL='https://voicebox.sh/download'
    CC_URL='curl -fsSL https://chatcut.io/install.sh | sh'
    ;;
esac

# ---------------------------------------------------------------- Voicebox
VB_APP="$(find_app 'Voicebox.app' \
  '/Applications/Voicebox.app' \
  "$HOME/Applications/Voicebox.app" \
  '/Applications/Voicebox Desktop.app' 2>/dev/null || true)"
VB_EXE=''

if [ -n "${VB_APP:-}" ] && [ -d "$VB_APP" ]; then
  VB_EXE="$VB_APP"
fi

VB_RUNNING=0
tcp_open '127.0.0.1' "$PORT" && VB_RUNNING=1
VB_LAUNCHED=0

if [ "$VB_RUNNING" = 1 ]; then
  [ -z "$VB_EXE" ] && VB_EXE='(running, path unknown)'
  VB_STATE='ready'
elif [ -n "$VB_EXE" ]; then
  VB_STATE='installed-not-running'
  if [ "$NO_LAUNCH" = 0 ] && launch_app "$VB_EXE"; then
    i=0
    while [ "$i" -lt "$VB_WAIT" ]; do
      sleep 1
      i=$((i + 1))
      if tcp_open '127.0.0.1' "$PORT"; then
        VB_RUNNING=1
        VB_LAUNCHED=1
        VB_STATE='ready'
        break
      fi
    done
  fi
else
  VB_STATE='not-installed'
fi

case "$VB_STATE" in
  ready) VB_NOTE="API ready: http://127.0.0.1:$PORT/profiles" ;;
  installed-not-running)
    if [ "$NO_LAUNCH" = 1 ]; then
      VB_NOTE='Installed, not listening (--no-launch, so it was not started).'
    else
      VB_NOTE="Installed but did not listen within ${VB_WAIT}s. First run downloads models; ask the user to open it and wait."
    fi
    ;;
  *) VB_NOTE='Not installed. Give the user the install URL.' ;;
esac

# ---------------------------------------------------------------- ChatCut Desktop
CC_RUNNING=0
cc_running && CC_RUNNING=1

CC_APP="$(find_app 'ChatCut.app' \
  '/Applications/ChatCut.app' \
  "$HOME/Applications/ChatCut.app" 2>/dev/null || true)"
CC_EXE=''
if [ -n "${CC_APP:-}" ]; then CC_EXE="$CC_APP"; fi
if [ "$CC_RUNNING" = 1 ] && [ -z "$CC_EXE" ]; then
  CC_PID="$(pgrep -f 'ChatCut\.app/Contents/MacOS' 2>/dev/null | head -n 1)"
  if [ -n "${CC_PID:-}" ]; then
    CC_EXE="$(ps -o args= -p "$CC_PID" 2>/dev/null | sed -n 's#^\(/[^ ]*\.app\)/Contents/MacOS/.*#\1#p' | head -n 1)"
  fi
  [ -z "$CC_EXE" ] && CC_EXE='(running, path unknown)'
fi
CC_LAUNCHED=0

if [ "$PLATFORM" = linux ]; then
  CC_STATE='not-installed'
  CC_EXE=''
elif [ "$CC_RUNNING" = 1 ]; then
  CC_STATE='running'
elif [ -n "$CC_EXE" ]; then
  CC_STATE='installed-not-running'
  if [ "$NO_LAUNCH" = 0 ] && launch_app "$CC_EXE"; then
    i=0
    while [ "$i" -lt "$CC_WAIT" ]; do
      sleep 1
      i=$((i + 1))
      if cc_running; then
        CC_RUNNING=1
        CC_LAUNCHED=1
        CC_STATE='running'
        break
      fi
    done
  fi
else
  CC_STATE='not-installed'
fi

case "$CC_STATE" in
  running) CC_NOTE='Process running. MCP tools load at session start: if chatcut_desktop is missing from this conversation, ask the user to start a new chat.' ;;
  installed-not-running)
    if [ "$NO_LAUNCH" = 1 ]; then
      CC_NOTE='Installed, not running (--no-launch, so it was not started).'
    else
      CC_NOTE="Installed but no process after ${CC_WAIT}s. Ask the user to open it manually (first run needs sign-in)."
    fi
    ;;
  *)
    if [ "$PLATFORM" = linux ]; then
      CC_NOTE='Not installed, and Desktop has no Linux build. Stage 4 must run on macOS or Windows.'
    else
      CC_NOTE='Not installed. Give the user the install command.'
    fi
    ;;
esac

# ---------------------------------------------------------------- Node / Remotion
NODE_BIN=''
if command -v node >/dev/null 2>&1; then
  NODE_BIN="$(command -v node)"
fi

NODE_VER=''
NODE_MAJOR=0
if [ -n "$NODE_BIN" ]; then
  NODE_VER="$("$NODE_BIN" -v 2>/dev/null | tr -d 'v\r')"
  case "$NODE_VER" in
    ''|*[!0-9.]*) NODE_VER='' ;;
    *) NODE_MAJOR="${NODE_VER%%.*}" ;;
  esac
  case "$NODE_MAJOR" in ''|*[!0-9]*) NODE_MAJOR=0 ;; esac
fi

NODE_STRAY=''
if [ -z "$NODE_BIN" ]; then
  # Off-PATH installs: worth mentioning, but scripts invoke plain `node`, so still not usable.
  for cand in /opt/homebrew/bin/node /usr/local/bin/node "$HOME"/.nvm/versions/node/*/bin/node; do
    if [ -x "$cand" ]; then NODE_STRAY="$cand"; break; fi
  done
fi

if [ -z "$NODE_BIN" ]; then
  NODE_STATE='not-installed'
elif [ "$NODE_MAJOR" -ge 22 ]; then
  NODE_STATE='ok'
else
  NODE_STATE='too-old'
fi

case "$NODE_STATE" in
  ok) NODE_NOTE='Remotion is pulled via npx on demand; no preinstall needed.' ;;
  too-old) NODE_NOTE="Below Node 22 (found v$NODE_VER): Remotion fails. Ask the user to upgrade." ;;
  *)
    if [ -n "$NODE_STRAY" ]; then
      NODE_NOTE="Not on PATH (found $NODE_STRAY). Neither Remotion nor scripts/tts.js can run until it is linked onto PATH."
    else
      NODE_NOTE='Not installed: neither Remotion nor scripts/tts.js can run.'
    fi
    ;;
esac

# ---------------------------------------------------------------- report
printf '=== video-production tool check ===\n'
[ "$PLATFORM" = linux ] && printf 'platform=linux (ChatCut Desktop unsupported here)\n'

emit() {
  name="$1"; state="$2"; detail="$3"; note="$4"; url="$5"; launched="$6"
  line="[$name] state=$state"
  [ -n "$detail" ] && line="$line $detail"
  printf '%s\n' "$line"
  [ -n "$note" ] && printf '    %s\n' "$note"
  if [ "$state" = 'not-installed' ] || [ "$state" = 'too-old' ]; then
    printf '    install: %s\n' "$url"
  fi
  [ "$launched" = 1 ] && printf '    launched by this script: yes\n'
  return 0
}

VB_DETAIL=''; CC_DETAIL=''; NODE_DETAIL=''
[ -n "$VB_EXE" ] && VB_DETAIL="path=$VB_EXE"
[ -n "$CC_EXE" ] && CC_DETAIL="path=$CC_EXE"
[ -n "$NODE_VER" ] && NODE_DETAIL="version=$NODE_VER"

emit 'voicebox' "$VB_STATE" "$VB_DETAIL" "$VB_NOTE" "$VB_URL" "$VB_LAUNCHED"
emit 'chatcut' "$CC_STATE" "$CC_DETAIL" "$CC_NOTE" "$CC_URL" "$CC_LAUNCHED"
emit 'node' "$NODE_STATE" "$NODE_DETAIL" "$NODE_NOTE" 'https://nodejs.org/en/download' 0

BLOCKED=''
[ "$VB_STATE" != 'ready' ] && BLOCKED="${BLOCKED}${BLOCKED:+, }Voicebox"
[ "$CC_STATE" != 'running' ] && BLOCKED="${BLOCKED}${BLOCKED:+, }ChatCut"
[ "$NODE_STATE" != 'ok' ] && BLOCKED="${BLOCKED}${BLOCKED:+, }Node"

printf '\n'
if [ -z "$BLOCKED" ]; then
  printf 'RESULT: ALL_READY\n'
  exit 0
fi
printf 'RESULT: BLOCKED (%s)\n' "$BLOCKED"
printf 'Stage 3 (audio) needs Voicebox; stage 4 (editing) needs ChatCut + Node.\n'
exit 2
