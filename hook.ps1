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

    $result = [pscustomobject]@{ Text = $null; Timestamp = $null }
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

        $result.Text = $text
        if ($entry.PSObject.Properties['timestamp']) {
            try { $result.Timestamp = [datetime]::Parse($entry.timestamp).ToLocalTime() } catch { }
        }
        break
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

# ── 알림 띄우기 (분리 프로세스, 즉시 반환) ──────────────────────────────
$notify = Join-Path $root 'notify.ps1'
try {
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$notify`"",
        '-Title',   "`"$title`"",
        '-Message', "`"$message`"",
        '-Detail',  "`"$detail`"",
        '-Sound',   "`"$($config.sound)`""
    ) | Out-Null
    Write-Log "알림: $title | $message | $detail"
} catch {
    Write-Log "알림 실행 실패: $_"
}

exit 0
