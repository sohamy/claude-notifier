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
    [string] $Detail  = ''
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
        [bool]   $Silent
    )

    # 등록 과정 없이 쓸 수 있는 내장 PowerShell AppId
    $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'

    $esc = { param($s) [System.Security.SecurityElement]::Escape([string]$s) }

    $lines = New-Object System.Text.StringBuilder
    [void]$lines.Append('<text>').Append((& $esc $Title)).Append('</text>')
    [void]$lines.Append('<text>').Append((& $esc $Message)).Append('</text>')
    if ($Detail) {
        [void]$lines.Append('<text placement="attribution">').Append((& $esc $Detail)).Append('</text>')
    }

    $audio = if ($Silent) { '<audio silent="true"/>' }
             else { '<audio src="ms-winsoundevent:Notification.Default"/>' }

    $xml = '<toast duration="short"><visual><binding template="ToastGeneric">' +
           $lines.ToString() +
           '</binding></visual>' + $audio + '</toast>'

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

    # 기본 소리: 시스템 알림음
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
        Show-WinRtToast -Title $Title -Message $Message -Detail $Detail -Silent $silentToast
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
