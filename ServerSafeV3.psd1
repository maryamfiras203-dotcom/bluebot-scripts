<###############################################
# MODULE: ServerSafeV3
# VERSION: 1.0.0
# AUTHOR: Maryam
# DESCRIPTION:
#   Server-safe scripting utilities including:
#     ✔ Structured logging
#     ✔ Certificate thumbprint lookup
#     ✔ CMS JSON encryption/decryption
#     ✔ Windows Credential Vault helpers
#     ✔ CMTrace log viewer
#
# SAFE FOR PUBLIC RELEASE
#   - No personal data
#   - No local paths
#   - No user IDs
#   - No real certificate names
#
# LICENSE:
#   MIT / BSD / GPL — choose your own license
###############################################>

# -------------------------------------------
# Script-scoped variables
# -------------------------------------------
$script:LogFile   = $null
$script:NoLog     = $false
$script:StartDT   = $null

################################################
# Start-ScriptV3
################################################
function Start-ScriptV3 {
<#
.SYNOPSIS
Initializes logging and script-runtime tracking.

.DESCRIPTION
Creates the log folder, generates a unique log file,
applies retention, and stores the script start time.

.PARAMETER LogPath
Custom log directory (default = "$PSScriptRoot\Logs")

.PARAMETER LogName
Base log name (default = invoking script name).

.PARAMETER RetentionDays
How many days logs are kept.

.PARAMETER NoLog
If specified, logging to file is disabled.

.EXAMPLE
Start-ScriptV3 -LogPath ".\Logs" -LogName "Backup.ps1"

.EXAMPLE
Start-ScriptV3 -NoLog

.OUTPUTS
System.DateTime
#>
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName="Log")]
        [string] $LogPath = "$PSScriptRoot\Logs",

        [Parameter(ParameterSetName="Log")]
        [string] $LogName = "Script",

        [Parameter(ParameterSetName="Log")]
        [int] $RetentionDays = 7,

        [Parameter(ParameterSetName="NoLog", Mandatory=$true)]
        [switch] $NoLog
    )

    $script:StartDT = Get-Date
    $script:NoLog   = $NoLog

    if ($NoLog) {
        Write-Host "[INFO] Script started at $($script:StartDT). Logging disabled."
        return $script:StartDT
    }

    if (!(Test-Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $script:LogFile = Join-Path $LogPath "$timestamp-$LogName.log"

    New-Item -ItemType File -Path $script:LogFile -Force | Out-Null
    Write-LogV3 -Type INFO -Message "Script started."

    # Log retention
    Get-ChildItem $LogPath -Filter "*.log" |
        Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-$RetentionDays) } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    return $script:StartDT
}

################################################
# Stop-ScriptV3
################################################
function Stop-ScriptV3 {
<#
.SYNOPSIS
Stops structured logging and calculates runtime.

.PARAMETER StartDateTime
Optional start time (defaults to Start-ScriptV3 timestamp)

.OUTPUTS
System.TimeSpan
#>
    [CmdletBinding()]
    param([datetime] $StartDateTime)

    if (-not $StartDateTime) {
        $StartDateTime = $script:StartDT
    }

    $EndDT = Get-Date
    $Runtime = New-TimeSpan -Start $StartDateTime -End $EndDT

    Write-LogV3 -Type INFO -Message "Script stopped."
    Write-LogV3 -Type INFO -Message "Runtime: $Runtime"

    return $Runtime
}

################################################
# Write-LogV3
################################################
function Write-LogV3 {
<#
.SYNOPSIS
Writes structured log messages to console & optionally file.

.PARAMETER Type
INFO / WARN / ERROR

.PARAMETER Message
Log message text
#>
    [CmdletBinding()]
    param(
        [ValidateSet("INFO","WARN","ERROR")]
        [string] $Type = "INFO",

        [Parameter(Mandatory=$true)]
        [string] $Message
    )

    $dt = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $line = "[$dt] [$Type] $Message"

    Write-Host $line

    if (-not $script:NoLog -and $script:LogFile) {
        Add-Content -Path $script:LogFile -Value $line -Encoding UTF8
    }
}

################################################
# Get-CertificateThumbprint
################################################
function Get-CertificateThumbprint {
<#
.SYNOPSIS
Returns the thumbprint of a certificate by CN name.

.PARAMETER DnsName
The CN= value to search for.

.PARAMETER Path
Certificate store path.

.OUTPUTS
String
#>
    param(
        [string]$DnsName,
        [string]$Path = "Cert:\LocalMachine\My"
    )
    $cert = Get-ChildItem -Path $Path |
        Where-Object { $_.Subject -eq "CN=$DnsName" } |
        Select-Object -First 1

    return $cert.Thumbprint
}

################################################
# Protect-SecretJson
################################################
function Protect-SecretJson {
<#
.SYNOPSIS
Encrypts JSON content using a CMS certificate.

.RETURNVALUE
0  = success
-1 = failure
#>
    param(
        [string] $json,
        [string] $certThumbprint,
        [string] $Path
    )

    try {
        $json | Protect-CmsMessage -To $certThumbprint -OutFile $Path
    }
    catch { return -1 }

    return 0
}

################################################
# Unprotect-SecretJson
################################################
function Unprotect-SecretJson {
<#
.SYNOPSIS
Decrypts CMS file into a PowerShell object.

.RETURNVALUE
object = success
-1     = failure
#>
    param(
        [string] $certThumbprint,
        [string] $Path
    )

    try {
        return (Unprotect-CmsMessage -To $certThumbprint -Path $Path) | ConvertFrom-Json
    }
    catch { return -1 }
}

################################################
# Open-CMTraceLog
################################################
function Open-CMTraceLog {
<#
.SYNOPSIS
Opens a log file in CMTrace.exe.

.DESCRIPTION
Automatically searches common CMTrace locations, but allows providing a custom path.

.PARAMETER Path
Log file path.

.PARAMETER CMTracePath
Custom path to CMTrace.exe.

.RETURNVALUE
0 = success  
-1 = failure  
#>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [string]$CMTracePath
    )

    if (-not (Test-Path $Path)) {
        Write-Host "[ERROR] Log file not found: $Path" -ForegroundColor Red
        return -1
    }

    if (-not $CMTracePath) {
        $CommonPaths = @(
            "C:\Windows\CMTrace.exe",
            "C:\CMTrace.exe",
            "$env:ProgramFiles\CMTrace\CMTrace.exe",
            "$env:ProgramFiles(x86)\CMTrace\CMTrace.exe"
        )
        $CMTracePath = $CommonPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    }

    if (-not (Test-Path $CMTracePath)) {
        Write-Host "[ERROR] CMTrace.exe not found" -ForegroundColor Red
        return -1
    }

    Start-Process -FilePath $CMTracePath -ArgumentList $Path
    return 0
}

################################################
# Windows Credential Vault Helpers
################################################

function Get-WindowsVaultCredential {
<#
.SYNOPSIS
Retrieves credentials from the Windows Credential Vault.

.OUTPUTS
PSCredential or -1
#>
    param(
        [string] $Resource,
        [string] $Username
    )

    [Windows.Security.Credentials.PasswordVault, Windows.Security.Credentials, ContentType=WindowsRuntime] | Out-Null
    $vault = New-Object Windows.Security.Credentials.PasswordVault

    try {
        $resp = $vault.Retrieve($Resource, $Username)
        return New-Object PSCredential (
            $resp.UserName,
            (ConvertTo-SecureString $resp.Password -AsPlainText -Force)
        )
    }
    catch {
        Write-Warning "Could not retrieve credential."
        return -1
    }
}

function Set-WindowsVaultCredential {
<#
.SYNOPSIS
Stores a new credential into the Windows Credential Vault.
#>
    [Windows.Security.Credentials.PasswordVault, Windows.Security.Credentials, ContentType=WindowsRuntime] | Out-Null
    $vault = New-Object Windows.Security.Credentials.PasswordVault

    try {
        $credential = Get-Credential
    }
    catch { return -1 }

    $resource = Read-Host "Resource"
    $credObj = New-Object Windows.Security.Credentials.PasswordCredential (
        $resource,
        $credential.UserName,
        $credential.GetNetworkCredential().Password
    )

    try { $vault.Add($credObj) }
    catch { Write-Warning "Could not store credential." }
}

function Remove-WindowsVaultCredential {
<#
.SYNOPSIS
Removes a credential from the Windows Credential Vault.
#>
    [Windows.Security.Credentials.PasswordVault, Windows.Security.Credentials, ContentType=WindowsRuntime] | Out-Null
    $vault = New-Object Windows.Security.Credentials.PasswordVault

    $credObj = New-Object Windows.Security.Credentials.PasswordCredential
    $credObj.Resource = Read-Host "Resource"
    $credObj.UserName = Read-Host "Username"

    try { $vault.Remove($credObj) }
    catch { Write-Warning "Could not remove credential." }
}

################################################
# Export Public Functions
################################################
Export-ModuleMember -Function *
