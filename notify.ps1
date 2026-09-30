<#
.SYNOPSIS
    윈도우 토스트 알림 + 소리를 띄운다. claude-notifier 의 실제 알림 표시 담당.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File notify.ps1 -Title "Claude Code" -Message "작업 완료"
#>
[CmdletBinding()]
param(
    [string] $Title   = 'Claude Code',
    [string] $Message = '작업이 완료되었습니다.',

    # default | none | <.wav 파일 경로>
    [string] $Sound   = 'default',

    # 토스트에 함께 보여줄 작은 보조 텍스트(경로, 소요시간 등)
    [string] $Detail  = '',

    # 클릭 시 열 URI. claude-notifier:focus?hwnd=...&pid=... 형태로
    # 터미널 창을 맨 앞으로 가져온다. 비우면 클릭해도 닫히기만 한다.
    [string] $LaunchUri = '',

    # 클릭하거나 닫을 때까지 화면에 남긴다
    [switch] $Persist
)

$ErrorActionPreference = 'Continue'

function Test-WinRtToast {
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime]
        return $true
    } catch {
        return $false
    }
}

function Show-WinRtToast {
    param(
        [string] $Title,
        [string] $Message,
        [string] $Detail,
        [string] $LaunchUri,
        [bool]   $Silent,
        [bool]   $Persist
    )

    # 등록 과정 없이 쓸 수 있는 내장 PowerShell AppId
    $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

    $esc = { param($s) [System.Security.SecurityElement]::Escape([string]$s) }

    $texts = New-Object System.Text.StringBuilder
    [void]$texts.Append('<text>').Append((& $esc $Title)).Append('</text>')
    [void]$texts.Append('<text>').Append((& $esc $Message)).Append('</text>')
    if ($Detail) {
        [void]$texts.Append('<text placement="attribution">').Append((& $esc $Detail)).Append('</text>')
    }

    $audio = if ($Silent) { '<audio silent="true"/>' }
             else { '<audio src="ms-winsoundevent:Notification.Default"/>' }

    # scenario="reminder" 는 사용자가 클릭하거나 닫을 때까지 화면에 남는다.
    # 대신 action 이 하나 이상 있어야 하므로 아래에서 항상 채운다.
    $rootAttrs = New-Object System.Text.StringBuilder
    if ($Persist) { [void]$rootAttrs.Append(' scenario="reminder"') }
    else          { [void]$rootAttrs.Append(' duration="short"') }

    $actions = New-Object System.Text.StringBuilder
    if ($LaunchUri) {
        $uri = & $esc $LaunchUri
        [void]$rootAttrs.Append(' activationType="protocol" launch="').Append($uri).Append('"')
        [void]$actions.Append('<action content="Claude 창 열기" activationType="protocol" arguments="').Append($uri).Append('"/>')
    }
    if ($Persist) {
        # reminder 시나리오에는 닫을 방법을 반드시 남겨둔다
        [void]$actions.Append('<action content="닫기" activationType="system" arguments="dismiss"/>')
    }

    $actionsXml = if ($actions.Length -gt 0) { '<actions>' + $actions.ToString() + '</actions>' } else { '' }

    # 요소 순서는 스키마대로 visual -> audio -> actions
    $xml = '<toast' + $rootAttrs.ToString() + '>' +
           '<visual><binding template="ToastGeneric">' + $texts.ToString() + '</binding></visual>' +
           $audio + $actionsXml +
           '</toast>'

    $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
    $doc.LoadXml($xml)

    $toast = New-Object Windows.UI.Notifications.ToastNotification $doc
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
}

function Show-BalloonFallback {
    param(
        [string] $Title,
        [string] $Message
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $icon = New-Object System.Windows.Forms.NotifyIcon
    $icon.Icon = [System.Drawing.SystemIcons]::Information
    $icon.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Info
    $icon.BalloonTipTitle = $Title
    $icon.BalloonTipText  = $Message
    $icon.Visible = $true
    $icon.ShowBalloonTip(10000)

    Start-Sleep -Seconds 8

    $icon.Visible = $false
    $icon.Dispose()
}

function Invoke-Sound {
    param([string] $Sound)

    if ($Sound -eq 'none') { return }

    if ($Sound -ne 'default' -and (Test-Path -LiteralPath $Sound)) {
        try {
            $player = New-Object System.Media.SoundPlayer -ArgumentList $Sound
            $player.PlaySync()
            return
        } catch { }
    }

    try {
        [System.Media.SystemSounds]::Exclamation.Play()
    } catch {
        [console]::beep(880, 200)
        [console]::beep(1174, 250)
    }
}

# ── 실행 ────────────────────────────────────────────────────────────────
$customWav = ($Sound -ne 'default' -and $Sound -ne 'none' -and (Test-Path -LiteralPath $Sound))

# 커스텀 wav 를 쓰면 토스트는 무음으로 띄우고 소리는 따로 재생한다
$silentToast = ($Sound -eq 'none') -or $customWav

if (Test-WinRtToast) {
    try {
        Show-WinRtToast -Title $Title -Message $Message -Detail $Detail `
                        -LaunchUri $LaunchUri -Silent $silentToast -Persist $Persist.IsPresent
        if ($customWav) { Invoke-Sound -Sound $Sound }
        exit 0
    } catch {
        Write-Verbose "토스트 실패, 폴백 사용: $_"
    }
}

# 폴백: 풍선 알림 + 소리 직접 재생
if ($Sound -ne 'none') { Invoke-Sound -Sound $Sound }
Show-BalloonFallback -Title $Title -Message $(if ($Detail) { "$Message`n$Detail" } else { $Message })
exit 0
