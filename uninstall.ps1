<#
.SYNOPSIS
    settings.json 에서 claude-notifier Stop 훅만 제거한다. 다른 훅은 건드리지 않는다.
#>
[CmdletBinding()]
param(
    [ValidateSet('User', 'Project')]
    [string] $Scope = 'User'
)

$ErrorActionPreference = 'Stop'

$settingsPath = if ($Scope -eq 'User') {
    Join-Path $env:USERPROFILE '.claude\settings.json'
} else {
    Join-Path (Get-Location).Path '.claude\settings.json'
}

$root     = Split-Path -Parent $MyInvocation.MyCommand.Path
$hookPath = Join-Path $root 'hook.ps1'

if (-not (Test-Path -LiteralPath $settingsPath)) {
    Write-Host "설정 파일이 없습니다: $settingsPath" -ForegroundColor Yellow
    exit 0
}

function Test-OurHook {
    param($Entry)

    if (-not $Entry -or -not $Entry['command']) { return $false }
    $cmd = [string]$Entry['command']

    # 이 저장소의 hook.ps1 절대 경로로 판별한다 — clone 폴더 이름이
    # claude-notifier 가 아니어도 제대로 찾는다
    if ($cmd.IndexOf($hookPath, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }

    # 폴더명으로 매칭하던 예전 설치분도 거둬간다
    return ($cmd -like '*claude-notifier*hook.ps1*')
}

function ConvertTo-Hashtable {
    param($Object)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { return $Object }
    if ($Object -is [System.Management.Automation.PSCustomObject]) {
        $table = [ordered]@{}
        foreach ($prop in $Object.PSObject.Properties) { $table[$prop.Name] = ConvertTo-Hashtable $prop.Value }
        return $table
    }
    if ($Object -is [System.Collections.IEnumerable] -and $Object -isnot [string]) {
        # 앞의 쉼표가 없으면 return 이 1개짜리 배열을 언롤링해서
        # 훅 그룹 하나뿐인 기존 설정이 배열 -> 객체로 뭉개진다
        return ,@(foreach ($item in $Object) { ConvertTo-Hashtable $item })
    }
    return $Object
}

$settings = ConvertTo-Hashtable ((Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8) | ConvertFrom-Json)

$backup = '{0}.bak-{1}' -f $settingsPath, (Get-Date -Format 'yyyyMMdd-HHmmss')
Copy-Item -LiteralPath $settingsPath -Destination $backup
Write-Host "백업: $backup" -ForegroundColor DarkGray

$removed = 0
if ($settings.Contains('hooks') -and $settings['hooks'].Contains('Stop')) {
    $kept = @()
    foreach ($group in @($settings['hooks']['Stop'])) {
        $entries = @(@($group['hooks']) | Where-Object { -not (Test-OurHook $_) })
        $removed += (@($group['hooks']).Count - $entries.Count)
        if ($entries.Count -gt 0) {
            $group['hooks'] = $entries
            $kept += $group
        }
    }

    if ($kept.Count -gt 0) { $settings['hooks']['Stop'] = $kept }
    else { $settings['hooks'].Remove('Stop') }

    if ($settings['hooks'].Count -eq 0) { $settings.Remove('hooks') }
}

$json = $settings | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding $false))

# ── claude-notifier: 프로토콜 등록 해제 ────────────────────────────────
$protoRoot = 'HKCU:\Software\Classes\claude-notifier'
if (Test-Path -LiteralPath $protoRoot) {
    Remove-Item -LiteralPath $protoRoot -Recurse -Force
    Write-Host '클릭 핸들러(claude-notifier: 프로토콜) 등록을 해제했습니다.' -ForegroundColor DarkGray
}

if ($removed -gt 0) {
    Write-Host "제거 완료 — claude-notifier 훅 $removed 개를 삭제했습니다." -ForegroundColor Green
} else {
    Write-Host '등록된 claude-notifier 훅이 없었습니다.' -ForegroundColor Yellow
}
