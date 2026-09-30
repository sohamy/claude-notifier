<#
.SYNOPSIS
    알림을 클릭했을 때 Claude Code 가 돌고 있는 터미널 창을 맨 앞으로 가져온다.

.DESCRIPTION
    claude-notifier: URL 프로토콜 핸들러로 등록돼 토스트 클릭 시 호출된다.
    install.ps1 이 HKCU 에 등록하고 uninstall.ps1 이 지운다.

.PARAMETER Uri
    claude-notifier:focus?hwnd=<핸들>&pid=<프로세스ID>
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string] $Uri = ''
)

$ErrorActionPreference = 'Continue'

$root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$logFile = Join-Path $root 'logs\notifier.log'

function Write-Log {
    param([string] $Message)
    try {
        $dir = Split-Path -Parent $logFile
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Add-Content -LiteralPath $logFile -Encoding UTF8 -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
    } catch { }
}

Add-Type -Namespace ClaudeNotifier -Name Win -MemberDefinition @'
    public delegate bool EnumProc(System.IntPtr hWnd, System.IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, System.IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(System.IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindow(System.IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(System.IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(System.IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(System.IntPtr hWnd, System.Text.StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
'@

$SW_RESTORE = 9
$SW_SHOW    = 5

function Set-ForegroundWindowHard {
    param([IntPtr] $Handle)

    if ($Handle -eq [IntPtr]::Zero -or -not [ClaudeNotifier.Win]::IsWindow($Handle)) { return $false }

    if ([ClaudeNotifier.Win]::IsIconic($Handle)) {
        [void][ClaudeNotifier.Win]::ShowWindow($Handle, $SW_RESTORE)
    } else {
        [void][ClaudeNotifier.Win]::ShowWindow($Handle, $SW_SHOW)
    }

    if ([ClaudeNotifier.Win]::SetForegroundWindow($Handle)) { return $true }

    # 윈도우는 포그라운드 강제 전환을 막는다. 현재 포그라운드 창의 입력
    # 스레드에 잠깐 붙으면 우리 호출도 허용된다.
    $foreground = [ClaudeNotifier.Win]::GetForegroundWindow()
    $fgPid      = 0
    $fgThread   = [ClaudeNotifier.Win]::GetWindowThreadProcessId($foreground, [ref]$fgPid)
    $myThread   = [ClaudeNotifier.Win]::GetCurrentThreadId()

    $attached = $false
    $ok = $false
    try {
        if ($fgThread -ne 0 -and $fgThread -ne $myThread) {
            $attached = [ClaudeNotifier.Win]::AttachThreadInput($myThread, $fgThread, $true)
        }
        [void][ClaudeNotifier.Win]::BringWindowToTop($Handle)
        $ok = [ClaudeNotifier.Win]::SetForegroundWindow($Handle)
    } finally {
        if ($attached) { [void][ClaudeNotifier.Win]::AttachThreadInput($myThread, $fgThread, $false) }
    }

    return $ok
}

function Get-WindowsForPid {
    param([int] $ProcessId)

    # Process.MainWindowHandle 은 상황에 따라 0 을 돌려주므로 직접 훑는다
    $windows = New-Object System.Collections.ArrayList
    $callback = [ClaudeNotifier.Win+EnumProc] {
        param($handle, $lParam)
        $owner = 0
        [void][ClaudeNotifier.Win]::GetWindowThreadProcessId($handle, [ref]$owner)
        if ($owner -eq $ProcessId -and
            [ClaudeNotifier.Win]::IsWindowVisible($handle) -and
            [ClaudeNotifier.Win]::GetWindowTextLength($handle) -gt 0) {
            $sb = New-Object System.Text.StringBuilder 512
            [void][ClaudeNotifier.Win]::GetWindowText($handle, $sb, $sb.Capacity)
            [void]$windows.Add([pscustomobject]@{ Handle = $handle; Title = $sb.ToString() })
        }
        return $true
    }
    [void][ClaudeNotifier.Win]::EnumWindows($callback, [IntPtr]::Zero)
    return $windows
}

function Select-ProjectWindow {
    <#
        Windows Terminal 은 창이 여러 개여도 프로세스가 하나여서 hook.ps1 이
        넘겨준 대표 핸들이 엉뚱한 창일 수 있다. 제목에 프로젝트 이름이 든
        창이 있으면 그쪽을 고른다.
    #>
    param([int] $ProcessId, [string] $ProjectName)

    if ($ProcessId -le 0 -or -not $ProjectName) { return [IntPtr]::Zero }

    $windows = Get-WindowsForPid -ProcessId $ProcessId
    if ($windows.Count -le 1) { return [IntPtr]::Zero }

    $match = $windows | Where-Object { $_.Title -like "*$ProjectName*" } | Select-Object -First 1
    if ($match) {
        Write-Log ("창 {0}개 중 제목으로 선택: '{1}'" -f $windows.Count, $match.Title)
        return $match.Handle
    }
    return [IntPtr]::Zero
}

function Set-ForegroundByPid {
    param([int] $ProcessId)

    if ($ProcessId -le 0) { return $false }

    try {
        $proc = Get-Process -Id $ProcessId -ErrorAction Stop
        if ($proc.MainWindowHandle -ne 0 -and (Set-ForegroundWindowHard -Handle $proc.MainWindowHandle)) {
            return $true
        }
    } catch {
        return $false   # 프로세스가 이미 없다
    }

    foreach ($window in (Get-WindowsForPid -ProcessId $ProcessId)) {
        if (Set-ForegroundWindowHard -Handle $window.Handle) { return $true }
    }

    try {
        $shell = New-Object -ComObject WScript.Shell
        return [bool]$shell.AppActivate($ProcessId)
    } catch {
        return $false
    }
}

# ── URI 파싱 ────────────────────────────────────────────────────────────
# claude-notifier:focus?hwnd=264766&pid=34444
$handleValue = 0L
$pidValue    = 0

$projectName = ''

if ($Uri -match '[?&]hwnd=(\d+)')      { $handleValue = [int64]$Matches[1] }
if ($Uri -match '[?&]pid=(\d+)')       { $pidValue    = [int]$Matches[1] }
if ($Uri -match '[?&]project=([^&]*)')  { $projectName = [uri]::UnescapeDataString($Matches[1]) }

if ($handleValue -eq 0 -and $pidValue -eq 0) {
    Write-Log "포커스 실패: URI 에서 창 정보를 찾지 못함 ('$Uri')"
    exit 0
}

$ok = $false

# 창이 여러 개면 제목이 맞는 쪽을 먼저 시도한다
$preferred = Select-ProjectWindow -ProcessId $pidValue -ProjectName $projectName
if ($preferred -ne [IntPtr]::Zero) { $ok = Set-ForegroundWindowHard -Handle $preferred }

if (-not $ok -and $handleValue -ne 0) { $ok = Set-ForegroundWindowHard -Handle ([IntPtr]$handleValue) }
if (-not $ok)                        { $ok = Set-ForegroundByPid -ProcessId $pidValue }

if ($ok) {
    Write-Log ('포커스 이동: hwnd={0} pid={1}' -f $handleValue, $pidValue)
} else {
    Write-Log ('포커스 실패: hwnd={0} pid={1} — 창이 이미 닫혔을 수 있음' -f $handleValue, $pidValue)
}

exit 0
