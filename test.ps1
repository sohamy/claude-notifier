<#
.SYNOPSIS
    알림이 제대로 뜨는지 확인한다. 훅을 설치하기 전에 먼저 이걸 돌려볼 것.
#>
[CmdletBinding()]
param(
    # 실제 훅 경로(stdin JSON 포함)까지 함께 시험한다
    [switch] $IncludeHook
)

$root = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host '1) notify.ps1 직접 호출...' -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'notify.ps1') `
    -Title '✅ claude-notifier — 테스트' `
    -Message '알림이 이렇게 표시됩니다.' `
    -Detail '소요 12초  ·  D:\some\project'
Write-Host '   토스트가 떴는지 확인하세요 (알림 센터: Win+N)' -ForegroundColor DarkGray

if ($IncludeHook) {
    Write-Host ''
    Write-Host '2) hook.ps1 에 가짜 Stop 훅 JSON 전달...' -ForegroundColor Cyan

    $fakeTranscript = Join-Path $env:TEMP 'claude-notifier-test.jsonl'
    $ts = (Get-Date).AddSeconds(-95).ToUniversalTime().ToString('o')
    @(
        (@{ type = 'user'; timestamp = $ts; message = @{ role = 'user'; content = '테스트 코드 깨진 것 좀 고쳐줘' } } | ConvertTo-Json -Depth 10 -Compress)
    ) | Set-Content -LiteralPath $fakeTranscript -Encoding UTF8

    $payload = @{
        session_id       = 'test-session'
        transcript_path  = $fakeTranscript
        cwd              = (Get-Location).Path
        hook_event_name  = 'Stop'
        stop_hook_active = $false
    } | ConvertTo-Json -Depth 10 -Compress

    $payload | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'hook.ps1')

    Write-Host '   로그:' -ForegroundColor DarkGray
    Get-Content -LiteralPath (Join-Path $root 'logs\notifier.log') -Tail 3 -Encoding UTF8 |
        ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }

    Remove-Item -LiteralPath $fakeTranscript -ErrorAction SilentlyContinue
}
