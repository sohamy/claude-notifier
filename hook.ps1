<#
.SYNOPSIS
    Claude Code Stop 훅. stdin 으로 들어온 훅 JSON 을 읽어
    "무엇을 시켰고 얼마나 걸렸는지" 를 뽑아 알림을 띄운다.

.NOTES
    Claude Code 를 막지 않도록 notify.ps1 은 분리된 프로세스로 띄우고 즉시 종료한다.
    항상 exit 0 — 알림이 실패해도 Claude 작업 흐름을 깨지 않는다.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile = Join-Path $root 'logs\notifier.log'

function Write-Log {
    param([string] $Message)
    try {
        $dir = Split-Path -Parent $logFile
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
        Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    } catch { }
}

function Get-Config {
    $defaults = [ordered]@{
        enabled         = $true
        sound           = 'default'   # default | none | <.wav 경로>
        minSeconds      = 0           # 이 시간보다 짧게 끝난 턴은 알림 생략
        includePrompt   = $true       # 마지막 지시 내용을 알림에 포함
        promptMaxLength = 70
        includeProject  = $true       # 프로젝트 폴더명 표시
        quietHoursStart = ''          # 예: '23:00' (비우면 사용 안 함)
        quietHoursEnd   = ''          # 예: '08:00'

        # 사용자가 Esc 등으로 중단한 턴에도 알릴지
        notifyOnInterrupt   = $false
        # 클릭하거나 닫을 때까지 알림을 화면에 남긴다
        persistUntilClicked = $true
        # 알림을 클릭하면 Claude Code 가 돌던 터미널 창을 맨 앞으로 가져온다
        focusOnClick        = $true
    }

    $path = Join-Path $root 'config.json'
    if (Test-Path -LiteralPath $path) {
        try {
            $user = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($key in @($defaults.Keys)) {
                if ($null -ne $user.PSObject.Properties[$key]) {
                    $defaults[$key] = $user.$key
                }
            }
        } catch {
            Write-Log "config.json 파싱 실패, 기본값 사용: $_"
        }
    }
    return $defaults
}

function Test-QuietHours {
    param([string] $Start, [string] $End)

    if (-not $Start -or -not $End) { return $false }
    try {
        $now = (Get-Date).TimeOfDay
        $s   = [TimeSpan]::Parse($Start)
        $e   = [TimeSpan]::Parse($End)
        if ($s -le $e) { return ($now -ge $s -and $now -lt $e) }
        # 자정을 넘기는 구간 (예: 23:00 ~ 08:00)
        return ($now -ge $s -or $now -lt $e)
    } catch {
        return $false
    }
}

function Get-TextFromContent {
    param($Content)

    if ($null -eq $Content) { return $null }
    if ($Content -is [string]) { return $Content }

    $parts = @()
    foreach ($block in @($Content)) {
        if ($block -is [string]) { $parts += $block; continue }
        $type = $block.PSObject.Properties['type']
        if ($type -and $block.type -eq 'tool_result') { return $null }  # 도구 결과는 사용자 지시가 아니다
        if ($type -and $block.type -eq 'text' -and $block.PSObject.Properties['text']) {
            $parts += [string]$block.text
        }
    }
    if ($parts.Count -eq 0) { return $null }
    return ($parts -join ' ')
}

function Get-LastUserPrompt {
    param([string] $TranscriptPath)

    $result = [pscustomobject]@{ Text = $null; Timestamp = $null; Interrupted = $false }
    if (-not $TranscriptPath -or -not (Test-Path -LiteralPath $TranscriptPath)) { return $result }

    try {
        # 최근 400줄만 훑는다 — 긴 세션에서도 빠르게 끝난다
        # @() 로 감싼다 — 한 줄짜리 파일은 Get-Content 가 배열이 아닌 문자열을 돌려준다
        $lines = @(Get-Content -LiteralPath $TranscriptPath -Tail 400 -Encoding UTF8)
    } catch {
        Write-Log "transcript 읽기 실패: $_"
        return $result
    }

    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $line = [string]$lines[$i]
        if (-not $line -or $line.Trim().Length -eq 0) { continue }

        try { $entry = $line | ConvertFrom-Json } catch { continue }

        if ($entry.PSObject.Properties['type'] -and $entry.type -ne 'user') { continue }
        if ($entry.PSObject.Properties['isMeta'] -and $entry.isMeta) { continue }
        if (-not $entry.PSObject.Properties['message']) { continue }

        $text = Get-TextFromContent $entry.message.content
        if (-not $text) { continue }

        $text = $text.Trim()
        if ($text.Length -eq 0) { continue }
        # 훅/시스템이 끼워넣은 리마인더성 항목은 건너뛴다
        if ($text -like '<*') { continue }

        # 중단은 '[Request interrupted by user]' 라는 user 엔트리로 기록된다.
        # 뒤에서부터 훑으므로 실제 지시보다 이걸 먼저 만나면 그 턴은 중단된 것이다.
        if ($text -match '^\[Request interrupted by user') {
            $result.Interrupted = $true
            continue
        }

        $result.Text = $text
        if ($entry.PSObject.Properties['timestamp']) {
            try { $result.Timestamp = [datetime]::Parse($entry.timestamp).ToLocalTime() } catch { }
        }
        break
    }

    return $result
}

function Get-WindowCachePath { Join-Path $root 'logs\windows.json' }

function Get-CachedWindow {
    <#
        조상 사슬을 훑는 데 WMI 초기화까지 0.8초가 걸리고 그동안 Claude Code 가
        대기한다. 세션이 도는 동안 터미널 창은 바뀌지 않으므로 session_id 로
        캐싱해서 첫 턴에만 그 값을 치른다.
    #>
    param([string] $SessionId)

    if (-not $SessionId) { return $null }
    $path = Get-WindowCachePath
    if (-not (Test-Path -LiteralPath $path)) { return $null }

    try {
        $cache = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $entry = $cache.PSObject.Properties[$SessionId]
        if (-not $entry) { return $null }
        return [pscustomobject]@{
            Handle    = [int64]$entry.Value.hwnd
            ProcessId = [int]$entry.Value.pid
        }
    } catch {
        return $null
    }
}

function Set-CachedWindow {
    param([string] $SessionId, $Window)

    if (-not $SessionId -or -not $Window) { return }
    $path = Get-WindowCachePath

    try {
        $dir = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        $cache = [ordered]@{}
        if (Test-Path -LiteralPath $path) {
            $existing = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            $cutoff = (Get-Date).AddDays(-7)
            foreach ($prop in $existing.PSObject.Properties) {
                # 오래된 세션은 흘려보낸다
                try { if ([datetime]::Parse($prop.Value.at) -lt $cutoff) { continue } } catch { }
                $cache[$prop.Name] = $prop.Value
            }
        }

        $cache[$SessionId] = [ordered]@{
            hwnd = $Window.Handle
            pid  = $Window.ProcessId
            at   = (Get-Date).ToString('o')
        }

        $json = $cache | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding $false))
    } catch {
        Write-Log "창 캐시 저장 실패: $_"
    }
}

function Get-TerminalWindow {
    <#
        훅은 Claude Code 의 자식으로 돌기 때문에, 부모를 거슬러 올라가면
        터미널 창(Windows Terminal, conhost 등)을 만난다. 창을 들고 있는
        첫 조상을 알림 클릭 대상으로 삼는다.

        이 함수는 매 턴 끝에 돌고 그동안 Claude Code 가 대기하므로 가볍게
        유지한다. 창이 여러 개일 때 어느 것을 고를지는 클릭 시점의
        focus.ps1 이 판단한다.
    #>
    $result = [pscustomobject]@{ Handle = 0L; ProcessId = 0 }

    $current = $PID
    for ($depth = 0; $depth -lt 12; $depth++) {
        try {
            # 전체 프로세스를 훑지 않고 이 pid 만 물어본다
            $info = Get-CimInstance Win32_Process -Filter "ProcessId=$current" -ErrorAction Stop
            if (-not $info) { break }
            $current = [int]$info.ParentProcessId
        } catch {
            break
        }
        if ($current -le 4) { break }   # System / Idle 까지 올라갔다

        try {
            $proc = Get-Process -Id $current -ErrorAction Stop
            if ($proc.MainWindowHandle -ne 0) {
                $result.Handle    = [int64]$proc.MainWindowHandle
                $result.ProcessId = $current
                break
            }
        } catch { }
    }

    return $result
}

function Format-Duration {
    param([TimeSpan] $Span)

    # [int] 캐스트는 절삭이 아니라 반올림이므로 Floor 를 쓴다 (95초 -> '2분 35초' 방지)
    if ($Span.TotalSeconds -lt 1)  { return '1초 미만' }
    if ($Span.TotalSeconds -lt 60) { return ('{0}초' -f [math]::Floor($Span.TotalSeconds)) }
    if ($Span.TotalMinutes -lt 60) { return ('{0}분 {1}초' -f [math]::Floor($Span.TotalMinutes), $Span.Seconds) }
    return ('{0}시간 {1}분' -f [math]::Floor($Span.TotalHours), $Span.Minutes)
}

function Limit-Length {
    param([string] $Text, [int] $Max)

    $flat = ($Text -replace '\s+', ' ').Trim()
    if ($Max -gt 0 -and $flat.Length -gt $Max) {
        return $flat.Substring(0, $Max).TrimEnd() + '…'
    }
    return $flat
}

# ── stdin 읽기 ──────────────────────────────────────────────────────────
$payload = $null
try {
    $raw = [Console]::In.ReadToEnd()
    if ($raw -and $raw.Trim().Length -gt 0) { $payload = $raw | ConvertFrom-Json }
} catch {
    Write-Log "stdin JSON 파싱 실패: $_"
}

$config = Get-Config

if (-not $config.enabled) { exit 0 }

if (Test-QuietHours -Start $config.quietHoursStart -End $config.quietHoursEnd) {
    Write-Log '방해 금지 시간대 — 알림 생략'
    exit 0
}

# 훅이 자기 자신 때문에 다시 돈 경우 중복 알림 방지
if ($payload -and $payload.PSObject.Properties['stop_hook_active'] -and $payload.stop_hook_active) {
    exit 0
}

$cwd            = if ($payload -and $payload.cwd) { [string]$payload.cwd } else { (Get-Location).Path }
$transcriptPath = if ($payload -and $payload.transcript_path) { [string]$payload.transcript_path } else { '' }

$prompt  = Get-LastUserPrompt -TranscriptPath $transcriptPath
$elapsed = $null
if ($prompt.Timestamp) { $elapsed = (Get-Date) - $prompt.Timestamp }

if ($prompt.Interrupted -and -not $config.notifyOnInterrupt) {
    Write-Log '사용자가 중단한 턴 — 알림 생략'
    exit 0
}

if ($config.minSeconds -gt 0 -and $elapsed -and $elapsed.TotalSeconds -lt $config.minSeconds) {
    Write-Log ('짧은 턴({0:N0}초) — minSeconds={1} 이므로 생략' -f $elapsed.TotalSeconds, $config.minSeconds)
    exit 0
}

# ── 알림 문구 구성 ──────────────────────────────────────────────────────
$project = if ($cwd) { Split-Path -Leaf $cwd } else { '' }

$title = '✅ Claude 작업 완료'
if ($config.includeProject -and $project) { $title = "✅ $project — 작업 완료" }

$message = if ($config.includePrompt -and $prompt.Text) {
    Limit-Length -Text $prompt.Text -Max ([int]$config.promptMaxLength)
} else {
    'Claude Code 가 응답을 마쳤습니다.'
}

$detailParts = @()
if ($elapsed) { $detailParts += ('소요 {0}' -f (Format-Duration $elapsed)) }
if ($cwd)     { $detailParts += $cwd }
$detail = $detailParts -join '  ·  '

# 클릭했을 때 돌아올 창
$launchUri = ''
if ($config.focusOnClick) {
    $sessionId = if ($payload -and $payload.session_id) { [string]$payload.session_id } else { '' }

    $window = Get-CachedWindow -SessionId $sessionId
    if (-not $window) {
        $window = Get-TerminalWindow
        if ($window.Handle -ne 0 -or $window.ProcessId -ne 0) {
            Set-CachedWindow -SessionId $sessionId -Window $window
        }
    }

    if ($window -and ($window.Handle -ne 0 -or $window.ProcessId -ne 0)) {
        $launchUri = 'claude-notifier:focus?hwnd={0}&pid={1}&project={2}' -f
                     $window.Handle, $window.ProcessId, [uri]::EscapeDataString($project)
    } else {
        Write-Log '포커스 대상 창을 찾지 못해 클릭 동작 없이 알립니다'
    }
}

# ── 알림 띄우기 (분리 프로세스, 즉시 반환) ──────────────────────────────
$notify = Join-Path $root 'notify.ps1'
try {
    $notifyArgs = [System.Collections.ArrayList]@(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$notify`"",
        '-Title',   "`"$title`"",
        '-Message', "`"$message`"",
        '-Detail',  "`"$detail`"",
        '-Sound',   "`"$($config.sound)`""
    )
    if ($launchUri) { [void]$notifyArgs.AddRange(@('-LaunchUri', "`"$launchUri`"")) }
    if ($config.persistUntilClicked) { [void]$notifyArgs.Add('-Persist') }

    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList $notifyArgs | Out-Null
    Write-Log "알림: $title | $message | $detail | $(if ($launchUri) { $launchUri } else { '클릭 동작 없음' })"
} catch {
    Write-Log "알림 실행 실패: $_"
}

exit 0
