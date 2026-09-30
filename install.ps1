<#
.SYNOPSIS
    claude-notifier 를 Claude Code 의 Stop 훅으로 등록한다.

.PARAMETER Scope
    User    → %USERPROFILE%\.claude\settings.json (모든 프로젝트에 적용, 기본값)
    Project → 현재 폴더\.claude\settings.json (이 프로젝트만)

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -Scope Project
#>
[CmdletBinding()]
param(
    [ValidateSet('User', 'Project')]
    [string] $Scope = 'User'
)

$ErrorActionPreference = 'Stop'

$root     = Split-Path -Parent $MyInvocation.MyCommand.Path
$hookPath = Join-Path $root 'hook.ps1'
$command  = 'powershell -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $hookPath

$settingsPath = if ($Scope -eq 'User') {
    Join-Path $env:USERPROFILE '.claude\settings.json'
} else {
    Join-Path (Get-Location).Path '.claude\settings.json'
}

function ConvertTo-Hashtable {
    param($Object)

    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { return $Object }

    if ($Object -is [System.Management.Automation.PSCustomObject]) {
        $table = [ordered]@{}
        foreach ($prop in $Object.PSObject.Properties) {
            $table[$prop.Name] = ConvertTo-Hashtable $prop.Value
        }
        return $table
    }

    if ($Object -is [System.Collections.IEnumerable] -and $Object -isnot [string]) {
        # 앞의 쉼표가 없으면 return 이 1개짜리 배열을 언롤링해서
        # 훅 그룹 하나뿐인 기존 설정이 배열 -> 객체로 뭉개진다
        return ,@(foreach ($item in $Object) { ConvertTo-Hashtable $item })
    }

    return $Object
}

# ── 기존 설정 읽기 ──────────────────────────────────────────────────────
$settings = [ordered]@{}
if (Test-Path -LiteralPath $settingsPath) {
    $rawText = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8
    if ($rawText.Trim().Length -gt 0) {
        try {
            $settings = ConvertTo-Hashtable ($rawText | ConvertFrom-Json)
        } catch {
            throw "settings.json 을 읽을 수 없습니다 ($settingsPath). JSON 문법을 확인하세요.`n$_"
        }
    }

    $backup = '{0}.bak-{1}' -f $settingsPath, (Get-Date -Format 'yyyyMMdd-HHmmss')
    Copy-Item -LiteralPath $settingsPath -Destination $backup
    Write-Host "기존 설정 백업: $backup" -ForegroundColor DarkGray
} else {
    $dir = Split-Path -Parent $settingsPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

# ── Stop 훅 추가 (기존 훅은 유지) ───────────────────────────────────────
if (-not $settings.Contains('hooks') -or $null -eq $settings['hooks']) {
    $settings['hooks'] = [ordered]@{}
}
$hooks = $settings['hooks']

$stopGroups = @()
if ($hooks.Contains('Stop') -and $null -ne $hooks['Stop']) {
    $stopGroups = @($hooks['Stop'])
}

$already = $false
foreach ($group in $stopGroups) {
    foreach ($entry in @($group['hooks'])) {
        if ($entry -and $entry['command'] -and ([string]$entry['command']) -like "*claude-notifier*hook.ps1*") {
            $entry['command'] = $command   # 경로가 바뀐 경우 갱신
            $already = $true
        }
    }
}

if ($already) {
    Write-Host 'Stop 훅이 이미 등록돼 있어 명령만 최신 경로로 갱신했습니다.' -ForegroundColor Yellow
} else {
    $stopGroups += [ordered]@{
        hooks = @(
            [ordered]@{
                type    = 'command'
                command = $command
            }
        )
    }
}

$hooks['Stop'] = @($stopGroups)

# ── 저장 ────────────────────────────────────────────────────────────────
$json = $settings | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding $false))

Write-Host ''
Write-Host "설치 완료 ($Scope 범위)" -ForegroundColor Green
Write-Host "  설정 파일 : $settingsPath"
Write-Host "  훅 명령   : $command"
Write-Host ''
Write-Host '실행 중인 Claude Code 세션이 있으면 /hooks 로 등록 상태를 확인하거나 재시작하세요.' -ForegroundColor Cyan
