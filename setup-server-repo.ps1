[CmdletBinding()]
param(
    [string]$RepoUrl = "https://github.com/nwhitehouse-CSI/hello-world-demo-1.git",
    [string]$Branch = "main",
    [string]$RepoRoot = "C:\gitrepos",
    [string]$RepoName = "hello-world-demo-1"
)

$ErrorActionPreference = "Stop"

function Assert-CommandExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName
    )

    if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $CommandName"
    }
}

Assert-CommandExists -CommandName "git"

$repoPath = Join-Path $RepoRoot $RepoName

Write-Host "Preparing local repository..."
Write-Host "Repo URL  : $RepoUrl"
Write-Host "Branch    : $Branch"
Write-Host "Repo path : $repoPath"

if (-not (Test-Path -LiteralPath $RepoRoot)) {
    New-Item -ItemType Directory -Path $RepoRoot -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $repoPath)) {
    Write-Host "Cloning repository..."
    git clone --branch $Branch $RepoUrl $repoPath
}
else {
    $gitDir = Join-Path $repoPath ".git"

    if (-not (Test-Path -LiteralPath $gitDir)) {
        throw "The target path exists but is not a Git repository: $repoPath"
    }

    Write-Host "Existing repository found. Validating remote and branch..."

    $currentRemote = git -C $repoPath remote get-url origin 2>$null
    if (-not $currentRemote) {
        git -C $repoPath remote add origin $RepoUrl
    }
    elseif ($currentRemote.Trim() -ne $RepoUrl) {
        git -C $repoPath remote set-url origin $RepoUrl
    }

    git -C $repoPath fetch origin

    $branchExists = git -C $repoPath branch --list $Branch
    if (-not $branchExists) {
        git -C $repoPath checkout -b $Branch "origin/$Branch"
    }
    else {
        git -C $repoPath checkout $Branch
    }
}

Write-Host "Pulling the latest code from origin/$Branch..."
git -C $repoPath pull origin $Branch

Write-Host ""
Write-Host "Repository is ready."
Write-Host "Local path: $repoPath"
Write-Host "Next pull command:"
Write-Host "git -C `"$repoPath`" pull origin $Branch"
