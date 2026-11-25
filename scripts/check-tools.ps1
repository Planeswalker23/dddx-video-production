# Detect the video-production tool chain (Voicebox / ChatCut Desktop / Node), report what is missing,
# auto-launch what is installed but not running, and print the install URL for what is absent.
# ASCII-only on purpose: Windows PowerShell 5.1 misparses non-BOM UTF-8 scripts.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File check-tools.ps1 [-NoLaunch] [-Port 17493]
# Exit: 0 = all ready, 2 = blocked
param(
  [switch]$NoLaunch,
  [int]$Port = 17493
)

$ErrorActionPreference = 'SilentlyContinue'

function Test-Port([string]$Name, [int]$PortNum, [int]$TimeoutMs = 1500) {
  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $iar = $client.BeginConnect($Name, $PortNum, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
    $client.EndConnect($iar)
    return $true
  } catch {
    return $false
  } finally {
    $client.Close()
  }
}

# Look in common install dirs, then uninstall registry entries, for the app executable.
function Find-App([string[]]$NamePatterns, [string[]]$CommonPaths) {
  foreach ($p in $CommonPaths) {
    if (Test-Path $p) { return $p }
  }
  $roots = @(
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
  )
  foreach ($root in $roots) {
    foreach ($item in (Get-ItemProperty $root)) {
      $dn = $item.DisplayName
      if (-not $dn) { continue }
      foreach ($pat in $NamePatterns) {
        if ($dn -like "*$pat*") {
          $icon = $item.DisplayIcon
          if ($icon) {
            $iconPath = ($icon -replace ',\d+$', '').Trim('"')
            if ((Test-Path $iconPath) -and $iconPath -match '\.exe$') { return $iconPath }
          }
          $loc = $item.InstallLocation
          if ($loc -and (Test-Path $loc)) {
            $exe = Get-ChildItem $loc -Filter '*.exe' -Recurse -Depth 2 |
              Where-Object { $_.Name -like "*$pat*" } | Select-Object -First 1
            if ($exe) { return $exe.FullName }
          }
        }
      }
    }
  }
  return $null
}

# ---------- Voicebox ----------
$vbPaths = @(
  "$env:LOCALAPPDATA\Programs\Voicebox\Voicebox.exe",
  "$env:LOCALAPPDATA\Programs\voicebox\Voicebox.exe",
  "$env:PROGRAMFILES\Voicebox\Voicebox.exe",
  "${env:ProgramFiles(x86)}\Voicebox\Voicebox.exe"
)
$vbExe = Find-App @('Voicebox') $vbPaths
$vbRunning = Test-Port '127.0.0.1' $Port
$vbLaunched = $false

if ($vbRunning) {
  if (-not $vbExe) { $vbExe = '(running, path unknown)' }
  $vbState = 'ready'
} elseif ($vbExe) {
  $vbState = 'installed-not-running'
  if (-not $NoLaunch) {
    Start-Process -FilePath $vbExe | Out-Null
    for ($i = 0; $i -lt 45; $i++) {
      Start-Sleep -Milliseconds 1000
      if (Test-Port '127.0.0.1' $Port) { $vbRunning = $true; $vbLaunched = $true; break }
    }
    if ($vbRunning) { $vbState = 'ready' }
  }
} else {
  $vbState = 'not-installed'
}

$vbNote = switch ($vbState) {
  'ready'                 { "API ready: http://127.0.0.1:$Port/profiles" }
  'installed-not-running' {
    if ($NoLaunch) { 'Installed, not listening (-NoLaunch, so it was not started).' }
    else { 'Installed but did not listen within 45s. First run downloads models; ask the user to open it and wait.' }
  }
  default { 'Not installed. Give the user the install URL.' }
}

# ---------- ChatCut Desktop ----------
$ccPaths = @(
  "$env:LOCALAPPDATA\Programs\ChatCut\ChatCut.exe",
  "$env:LOCALAPPDATA\Programs\chatcut\ChatCut.exe",
  "$env:LOCALAPPDATA\ChatCut\ChatCut.exe",
  "$env:PROGRAMFILES\ChatCut\ChatCut.exe",
  "${env:ProgramFiles(x86)}\ChatCut\ChatCut.exe"
)
$ccExe = Find-App @('ChatCut') $ccPaths
$ccProc = Get-Process -Name 'ChatCut' -ErrorAction SilentlyContinue | Select-Object -First 1
$ccLaunched = $false

if (-not $ccExe -and $ccProc) { $ccExe = $ccProc.Path }

if ($ccProc) {
  $ccState = 'running'
} elseif ($ccExe) {
  $ccState = 'installed-not-running'
  if (-not $NoLaunch) {
    Start-Process -FilePath $ccExe | Out-Null
    for ($i = 0; $i -lt 25; $i++) {
      Start-Sleep -Milliseconds 1000
      $ccProc = Get-Process -Name 'ChatCut' -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($ccProc) { $ccState = 'running'; $ccLaunched = $true; break }
    }
  }
} else {
  $ccState = 'not-installed'
}

$ccNote = switch ($ccState) {
  'running' { 'Process running. MCP tools load at session start: if chatcut_desktop is missing from this conversation, ask the user to start a new chat.' }
  'installed-not-running' {
    if ($NoLaunch) { 'Installed, not running (-NoLaunch, so it was not started).' }
    else { 'Installed but no process after 25s. Ask the user to open it manually (first run needs sign-in).' }
  }
  default { 'Not installed. Give the user the install command.' }
}

# ---------- Node / Remotion ----------
$nodePath = (Get-Command node -ErrorAction SilentlyContinue).Source
$nodeVer = if ($nodePath) { (& node -v) -replace '^v', '' } else { $null }
$nodeMajor = if ($nodeVer) { [int]($nodeVer -split '\.')[0] } else { 0 }
$nodeOk = $nodeMajor -ge 22

$nodeState = if (-not $nodePath) { 'not-installed' } elseif ($nodeOk) { 'ok' } else { 'too-old' }
$nodeNote = switch ($nodeState) {
  'ok'      { 'Remotion is pulled via npx on demand; no preinstall needed.' }
  'too-old' { 'Below Node 22: Remotion fails. Ask the user to upgrade.' }
  default   { 'Not installed: neither Remotion nor scripts/tts.mjs can run.' }
}

# ---------- Report ----------
# PowerShell 5.1: an `if` statement is not a value inside a hash literal - precompute.
$vbDetail = ''
$ccDetail = ''
$nodeDetail = ''
if ($vbExe)   { $vbDetail = "path=$vbExe" }
if ($ccExe)   { $ccDetail = "path=$ccExe" }
if ($nodeVer) { $nodeDetail = "version=$nodeVer" }

$rows = @(
  @{ name = 'voicebox'; state = $vbState; detail = $vbDetail; note = $vbNote; url = 'https://voicebox.sh/download/windows' },
  @{ name = 'chatcut';  state = $ccState; detail = $ccDetail; note = $ccNote; url = 'irm https://chatcut.io/install.ps1 | iex' },
  @{ name = 'node';     state = $nodeState; detail = $nodeDetail; note = $nodeNote; url = 'https://nodejs.org/en/download' }
)

Write-Output '=== video-production tool check ==='
foreach ($r in $rows) {
  $line = "[$($r.name)] state=$($r.state)"
  if ($r.detail) { $line += " $($r.detail)" }
  Write-Output $line
  if ($r.note) { Write-Output "    $($r.note)" }
  if ($r.state -eq 'not-installed' -or $r.state -eq 'too-old') { Write-Output "    install: $($r.url)" }
  if ($vbLaunched -and $r.name -eq 'voicebox') { Write-Output '    launched by this script: yes' }
  if ($ccLaunched -and $r.name -eq 'chatcut')  { Write-Output '    launched by this script: yes' }
}

$blocked = @()
if ($vbState -ne 'ready') { $blocked += 'Voicebox' }
if ($ccState -ne 'running') { $blocked += 'ChatCut' }
if ($nodeState -ne 'ok') { $blocked += 'Node' }

Write-Output ''
if ($blocked.Count -eq 0) {
  Write-Output 'RESULT: ALL_READY'
  exit 0
} else {
  Write-Output "RESULT: BLOCKED ($($blocked -join ', '))"
  Write-Output 'Stage 3 (audio) needs Voicebox; stage 4 (editing) needs ChatCut + Node.'
  exit 2
}