# Hello World Demo for IIS

This repository contains a minimal static "Hello World" website and a PowerShell deployment script for Windows IIS.

## Files

- `index.html` - homepage for the demo site
- `site.css` - simple styling for the homepage
- `deploy.ps1` - deploys the site to IIS and binds it to port `8080`
- `setup-server-repo.ps1` - prepares a local Git clone on the server for pulls and deployments

## What the deployment script does

`deploy.ps1` performs the full IIS setup:

1. Verifies the script is running in an elevated PowerShell session.
2. Checks for IIS management prerequisites and installs them automatically when missing.
3. Imports the IIS PowerShell module (`WebAdministration`).
4. Copies the site files into `C:\inetpub\wwwroot\HelloWorldDemo`.
5. Creates or updates an IIS application pool named `HelloWorldDemoPool`.
6. Creates or updates an IIS website named `HelloWorldDemo`.
7. Configures the site to listen on HTTP port `8080`.
8. Starts the IIS website.

## Usage

Open an elevated PowerShell window on the IIS server, change into this repository, and run:

```powershell
.\deploy.ps1
```

After deployment, open:

```text
http://localhost:8080/
```

## Set up a local repo on the server

If you want the IIS server to maintain its own local clone for future `git pull` operations, run:

```powershell
.\setup-server-repo.ps1
```

By default, it will clone this repository to:

```text
C:\gitrepos\hello-world-demo-1
```

You can override the defaults if needed:

```powershell
.\setup-server-repo.ps1 -RepoUrl "https://github.com/nwhitehouse-CSI/hello-world-demo-1.git" -Branch "main" -RepoRoot "C:\gitrepos" -RepoName "hello-world-demo-1"
```

After setup, the server can update the local repo with:

```powershell
git -C "C:\gitrepos\hello-world-demo-1" pull origin main
```

## Optional parameters

You can override the defaults if needed:

```powershell
.\deploy.ps1 -SiteName "HelloWorldDemo" -AppPoolName "HelloWorldDemoPool" -DestinationPath "C:\inetpub\wwwroot\HelloWorldDemo" -Port 8080
```

Enable diagnostic output:

```powershell
.\deploy.ps1 -DebugMode
```

Skip automatic prerequisite installation and fail fast instead:

```powershell
.\deploy.ps1 -SkipPrerequisiteInstall
```

## IIS prerequisites

- IIS must be installed on the server.
- The PowerShell module `WebAdministration` must be available.
- The script must be run as Administrator.
