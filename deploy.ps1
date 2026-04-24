[CmdletBinding()]
param(
    [string]$SiteName = "HelloWorldDemo",
    [string]$AppPoolName = "HelloWorldDemoPool",
    [string]$DestinationPath = "C:\inetpub\wwwroot\HelloWorldDemo",
    [int]$Port = 8080
)

$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    Write-Host "Elevation required. Relaunching deploy script as Administrator..."

    $argumentList = @(
        "-NoProfile"
        "-ExecutionPolicy", "Bypass"
        "-File", ('"{0}"' -f $PSCommandPath)
        "-SiteName", ('"{0}"' -f $SiteName)
        "-AppPoolName", ('"{0}"' -f $AppPoolName)
        "-DestinationPath", ('"{0}"' -f $DestinationPath)
        "-Port", $Port
    )

    $process = Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argumentList -PassThru -Wait
    exit $process.ExitCode
}

Import-Module WebAdministration -ErrorAction Stop

if (-not (Get-PSDrive -Name "IIS" -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name "IIS" -PSProvider "WebAdministration" -Root "\" | Out-Null
}

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

if (-not (Test-Path -LiteralPath $DestinationPath)) {
    New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
}

Copy-Item -Path (Join-Path $sourcePath "*") -Destination $DestinationPath -Recurse -Force

if (-not (Test-Path "IIS:\AppPools\$AppPoolName")) {
    New-WebAppPool -Name $AppPoolName | Out-Null
}

Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name managedRuntimeVersion -Value ""
Set-ItemProperty "IIS:\AppPools\$AppPoolName" -Name processModel.identityType -Value "ApplicationPoolIdentity"

$existingSite = Get-Website -Name $SiteName -ErrorAction SilentlyContinue

if ($existingSite) {
    Stop-Website -Name $SiteName
    Set-ItemProperty "IIS:\Sites\$SiteName" -Name applicationPool -Value $AppPoolName
    Set-ItemProperty "IIS:\Sites\$SiteName" -Name physicalPath -Value $DestinationPath

    Get-WebBinding -Name $SiteName -Protocol "http" -ErrorAction SilentlyContinue |
        Remove-WebBinding

    New-WebBinding -Name $SiteName -Protocol "http" -Port $Port -IPAddress "*" -HostHeader "" | Out-Null
}
else {
    New-Website -Name $SiteName `
        -Port $Port `
        -IPAddress "*" `
        -PhysicalPath $DestinationPath `
        -ApplicationPool $AppPoolName | Out-Null
}

Start-Website -Name $SiteName

Write-Host ""
Write-Host "Deployment complete."
Write-Host "Browse to: http://localhost:$Port/"
