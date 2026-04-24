[CmdletBinding()]
param(
    [string]$SiteName = "HelloWorldDemo",
    [string]$AppPoolName = "HelloWorldDemoPool",
    [string]$DestinationPath = "C:\inetpub\wwwroot\HelloWorldDemo",
    [int]$Port = 8080,
    [switch]$DebugMode,
    [switch]$SkipPrerequisiteInstall
)

$ErrorActionPreference = "Stop"
$script:PauseOnError = $false

function Invoke-PauseForError {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host ""
    Write-Host $Message -ForegroundColor Yellow
    Read-Host "Press Enter to close this window"
}

function Write-ExceptionDetails {
    param(
        [Parameter(Mandatory = $true)]
        $ErrorRecord
    )

    Write-Host ""
    Write-Host "Error message:" -ForegroundColor Yellow
    Write-Host $ErrorRecord.Exception.Message -ForegroundColor Red

    if ($ErrorRecord.InvocationInfo -and $ErrorRecord.InvocationInfo.PositionMessage) {
        Write-Host ""
        Write-Host "Location:" -ForegroundColor Yellow
        Write-Host $ErrorRecord.InvocationInfo.PositionMessage -ForegroundColor Red
    }

    if ($ErrorRecord.ScriptStackTrace) {
        Write-Host ""
        Write-Host "Stack trace:" -ForegroundColor Yellow
        Write-Host $ErrorRecord.ScriptStackTrace -ForegroundColor Red
    }

    if ($ErrorRecord.Exception.InnerException) {
        Write-Host ""
        Write-Host "Inner exception:" -ForegroundColor Yellow
        Write-Host $ErrorRecord.Exception.InnerException.Message -ForegroundColor Red
    }
}

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-IsWindowsPowerShellDesktop {
    return $PSVersionTable.PSEdition -eq "Desktop"
}

function Convert-ToSingleQuotedPowerShellString {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    return "'" + ($Value -replace "'", "''") + "'"
}

function Write-DebugInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($DebugMode) {
        Write-Host "[DEBUG] $Message"
    }
}

function Invoke-DebugStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    Write-DebugInfo "Starting: $Description"
    & $Action
    Write-DebugInfo "Completed: $Description"
}

function Install-IISPrerequisites {
    Write-DebugInfo "Checking IIS prerequisite installation state"

    $webAdminModule = Get-Module -ListAvailable -Name "WebAdministration" | Select-Object -First 1
    if ($webAdminModule) {
        Write-DebugInfo "WebAdministration module already available at $($webAdminModule.Path)"
        return
    }

    if ($SkipPrerequisiteInstall) {
        throw "The 'WebAdministration' module is not available and -SkipPrerequisiteInstall was specified."
    }

    $serverManager = Get-Command Install-WindowsFeature -ErrorAction SilentlyContinue
    if ($serverManager) {
        Write-DebugInfo "Installing IIS prerequisites with Install-WindowsFeature"
        $result = Install-WindowsFeature -Name Web-Server,Web-Scripting-Tools -IncludeManagementTools
        Write-DebugInfo "Install-WindowsFeature Success=$($result.Success) RestartNeeded=$($result.RestartNeeded) ExitCode=$($result.ExitCode)"

        if (-not $result.Success) {
            throw @"
Failed to install IIS prerequisites with Install-WindowsFeature.
ExitCode: $($result.ExitCode)
RestartNeeded: $($result.RestartNeeded)

Install-WindowsFeature did not report success. Check Server Manager / feature installation logs on the server.
"@
        }

        if ($result.RestartNeeded -and $result.RestartNeeded -ne "No") {
            throw @"
IIS prerequisites were installed, but Windows reported that a restart is required before PowerShell can use them.

Restart the server, then rerun:
.\deploy.ps1 -DebugMode
"@
        }

        return
    }

    $desktopFeatureCmd = Get-Command Enable-WindowsOptionalFeature -ErrorAction SilentlyContinue
    if ($desktopFeatureCmd) {
        Write-DebugInfo "Installing IIS prerequisites with Enable-WindowsOptionalFeature"
        $featureNames = @(
            "IIS-WebServerRole",
            "IIS-ManagementScriptingTools"
        )

        foreach ($featureName in $featureNames) {
            $featureResult = Enable-WindowsOptionalFeature -Online -FeatureName $featureName -All -NoRestart
            Write-DebugInfo "Enable-WindowsOptionalFeature $featureName RestartNeeded=$($featureResult.RestartNeeded) State=$($featureResult.State)"

            if ($featureResult.RestartNeeded) {
                throw @"
Windows enabled IIS feature '$featureName', but a restart is required before deployment can continue.

Restart the machine, then rerun:
.\deploy.ps1 -DebugMode
"@
            }
        }
        return
    }

    throw @"
Unable to install IIS prerequisites automatically.

Neither 'Install-WindowsFeature' nor 'Enable-WindowsOptionalFeature' is available on this system.
Install IIS plus the management scripting tools manually, then rerun the script.
"@
}

function Initialize-IISAdministration {
    Install-IISPrerequisites

    $module = Get-Module -ListAvailable -Name "WebAdministration" | Select-Object -First 1
    if (-not $module) {
        throw @"
The PowerShell module 'WebAdministration' is not available on this server.

The prerequisite installation step completed, but the module is still missing in the current OS state.

Verify these commands on the server:
Get-WindowsFeature Web-Server,Web-Scripting-Tools
Get-Module -ListAvailable WebAdministration

If the feature install reports RestartNeeded, reboot the server and rerun:
.\deploy.ps1 -DebugMode
"@
    }

    Write-DebugInfo "Importing WebAdministration from $($module.Path)"
    Import-Module WebAdministration -ErrorAction Stop

    $provider = Get-PSProvider -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "WebAdministration" }
    if (-not $provider) {
        throw @"
The 'WebAdministration' PowerShell provider did not load.

This usually means IIS management scripting components are missing or not fully installed.
Install the IIS scripting tools feature, then rerun the script:
Install-WindowsFeature Web-Scripting-Tools
"@
    }

    if (-not (Get-PSDrive -Name "IIS" -ErrorAction SilentlyContinue)) {
        Write-DebugInfo "Creating IIS PowerShell drive"
        New-PSDrive -Name "IIS" -PSProvider "WebAdministration" -Root "\" | Out-Null
    }
}

if ((-not (Test-IsAdministrator)) -or (-not (Test-IsWindowsPowerShellDesktop))) {
    $relaunchReasons = @()

    if (-not (Test-IsAdministrator)) {
        $relaunchReasons += "administrator privileges"
    }

    if (-not (Test-IsWindowsPowerShellDesktop)) {
        $relaunchReasons += "Windows PowerShell"
    }

    Write-Host ("Relaunching deploy script with {0}..." -f ($relaunchReasons -join " and "))

    $innerArguments = @(
        "-SiteName " + (Convert-ToSingleQuotedPowerShellString -Value $SiteName)
        "-AppPoolName " + (Convert-ToSingleQuotedPowerShellString -Value $AppPoolName)
        "-DestinationPath " + (Convert-ToSingleQuotedPowerShellString -Value $DestinationPath)
        "-Port $Port"
    )

    if ($DebugMode) {
        $innerArguments += "-DebugMode"
    }

    if ($SkipPrerequisiteInstall) {
        $innerArguments += "-SkipPrerequisiteInstall"
    }

    $scriptPathLiteral = Convert-ToSingleQuotedPowerShellString -Value $PSCommandPath
    $wrappedCommand = @"
try {
    & $scriptPathLiteral $($innerArguments -join ' ')
}
catch {
    Write-Host ''
    Write-Host 'Deployment failed in elevated window.' -ForegroundColor Yellow
    Write-Host 'Error message:' -ForegroundColor Yellow
    Write-Host `$_.Exception.Message -ForegroundColor Red
    if (`$_.InvocationInfo -and `$_.InvocationInfo.PositionMessage) {
        Write-Host ''
        Write-Host 'Location:' -ForegroundColor Yellow
        Write-Host `$_.InvocationInfo.PositionMessage -ForegroundColor Red
    }
    if (`$_.ScriptStackTrace) {
        Write-Host ''
        Write-Host 'Stack trace:' -ForegroundColor Yellow
        Write-Host `$_.ScriptStackTrace -ForegroundColor Red
    }
    Read-Host 'Press Enter to close this window'
}
"@

    $argumentList = @(
        "-NoProfile"
        "-ExecutionPolicy", "Bypass"
        "-NoExit"
        "-Command", $wrappedCommand
    )

    $process = Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argumentList -PassThru -Wait
    exit $process.ExitCode
}

if (Test-IsWindowsPowerShellDesktop) {
    $script:PauseOnError = $true
}

try {
    Write-DebugInfo "Running as administrator in Windows PowerShell $($PSVersionTable.PSVersion)"
    Initialize-IISAdministration

    $sourcePath = Split-Path -Parent $MyInvocation.MyCommand.Path
    if (-not $sourcePath) {
        throw "Unable to determine the source path for deployment files."
    }

    $requiredFiles = @("index.html", "site.css")
    foreach ($file in $requiredFiles) {
        $fullPath = Join-Path $sourcePath $file
        if (-not (Test-Path -LiteralPath $fullPath)) {
            throw "Required file not found: $fullPath"
        }
    }

    Write-Host "Deploying '$SiteName' to IIS..."
    Write-Host "Source path      : $sourcePath"
    Write-Host "Destination path : $DestinationPath"
    Write-Host "Port             : $Port"
    Write-DebugInfo "IIS PSDrive available: $([bool](Get-PSDrive -Name 'IIS' -ErrorAction SilentlyContinue))"

    Invoke-DebugStep -Description "Ensure destination folder exists" -Action {
        if (-not (Test-Path -LiteralPath $DestinationPath)) {
            New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
        }
    }

    Invoke-DebugStep -Description "Copy site files to destination" -Action {
        Copy-Item -Path (Join-Path $sourcePath "*") -Destination $DestinationPath -Recurse -Force
    }

    Invoke-DebugStep -Description "Ensure IIS app pool exists" -Action {
        if (-not (Test-Path "IIS:\AppPools\$AppPoolName")) {
            New-WebAppPool -Name $AppPoolName | Out-Null
        }
    }

    Invoke-DebugStep -Description "Set app pool runtime" -Action {
        Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name managedRuntimeVersion -Value ""
    }

    Invoke-DebugStep -Description "Set app pool identity" -Action {
        Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name processModel.identityType -Value "ApplicationPoolIdentity"
    }

    $existingSite = $null
    Invoke-DebugStep -Description "Lookup existing IIS site" -Action {
        $script:existingSiteLookup = Get-Website -Name $SiteName -ErrorAction SilentlyContinue
    }
    $existingSite = $script:existingSiteLookup

    if ($existingSite) {
        Invoke-DebugStep -Description "Stop existing IIS site" -Action {
            Stop-Website -Name $SiteName
        }
        Invoke-DebugStep -Description "Assign app pool to existing IIS site" -Action {
            Set-ItemProperty "IIS:\Sites\$SiteName" -Name applicationPool -Value $AppPoolName
        }
        Invoke-DebugStep -Description "Update existing IIS site physical path" -Action {
            Set-ItemProperty "IIS:\Sites\$SiteName" -Name physicalPath -Value $DestinationPath
        }

        Invoke-DebugStep -Description "Remove existing HTTP bindings" -Action {
            Get-WebBinding -Name $SiteName -Protocol "http" -ErrorAction SilentlyContinue |
                Remove-WebBinding
        }

        Invoke-DebugStep -Description "Create HTTP binding on port $Port" -Action {
            New-WebBinding -Name $SiteName -Protocol "http" -Port $Port -IPAddress "*" -HostHeader "" | Out-Null
        }
    }
    else {
        Invoke-DebugStep -Description "Create IIS website" -Action {
            New-Website -Name $SiteName `
                -Port $Port `
                -IPAddress "*" `
                -PhysicalPath $DestinationPath `
                -ApplicationPool $AppPoolName | Out-Null
        }
    }

    Invoke-DebugStep -Description "Start IIS website" -Action {
        Start-Website -Name $SiteName
    }

    Write-Host ""
    Write-Host "Deployment complete."
    Write-Host "Browse to: http://localhost:$Port/"
}
catch {
    Write-Error $_
    if ($script:PauseOnError) {
        Write-ExceptionDetails -ErrorRecord $_
        Invoke-PauseForError -Message "Deployment failed."
    }
    throw
}
