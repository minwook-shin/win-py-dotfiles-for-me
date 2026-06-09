<#
.SYNOPSIS
    Bootstrap a minimal Python development environment on a clean Windows 11 machine.
    Run via: iwr <url> -OutFile setup.ps1 -UseBasicParsing; powershell -ExecutionPolicy Bypass -File setup.ps1

.DESCRIPTION
    Installs Python (MS Store), upgrades pip, installs uv, installs Git, and optionally
    installs VS Code and the AWS CLI. Safe to re-run on an already configured machine.

.PARAMETER GitName
    Value for git config user.name.

.PARAMETER GitEmail
    Value for git config user.email.

.PARAMETER PythonVersion
    Python version to install (default: 3.13).

.PARAMETER InstallVSCode
    Switch — install VS Code and Python extensions.

.PARAMETER InstallAwsCli
    Switch — install AWS CLI via the official MSI.

.PARAMETER EnvFile
    Path to a .env config file (default: .\git-config.env next to the script).

.EXAMPLE
    .\setup.ps1 -GitName "Jane Smith" -GitEmail "jane@example.com" -InstallVSCode

.EXAMPLE
    .\setup.ps1  # reads git-config.env if present
#>

[CmdletBinding()]
param(
    [string]$GitName,
    [string]$GitEmail,
    [string]$PythonVersion = "3.13",
    [switch]$InstallVSCode,
    [switch]$InstallAwsCli,
    [string]$EnvFile = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $EnvFile) {
    $EnvFile = if ($PSScriptRoot) { Join-Path $PSScriptRoot "git-config.env" } else { "git-config.env" }
}

# ---------------------------------------------------------------------------
# Elevation check
# ---------------------------------------------------------------------------
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[WARN]  ! Script is not running as Administrator. Re-launching elevated..." -ForegroundColor DarkYellow
    $argList = [System.Collections.Generic.List[string]]::new()
    $argList.Add("-NoProfile")
    $argList.Add("-ExecutionPolicy")
    $argList.Add("Bypass")
    $argList.Add("-File")
    $argList.Add("`"$PSCommandPath`"")
    foreach ($kv in $MyInvocation.BoundParameters.GetEnumerator()) {
        if ($kv.Value -is [switch]) {
            if ($kv.Value) { $argList.Add("-$($kv.Key)") }
        } else {
            $argList.Add("-$($kv.Key)")
            $argList.Add("`"$($kv.Value)`"")
        }
    }
    Start-Process -FilePath "powershell.exe" -ArgumentList ($argList -join " ") -Verb RunAs
    exit
}

# ---------------------------------------------------------------------------
# Summary tracking
# ---------------------------------------------------------------------------
$summary = [System.Collections.Generic.List[PSCustomObject]]::new()

function Add-Summary {
    param([string]$Tool, [string]$Version, [string]$Status)
    $summary.Add([PSCustomObject]@{ Tool = $Tool; Version = $Version; Status = $Status })
}

# ---------------------------------------------------------------------------
# Env file loading (params take precedence)
# ---------------------------------------------------------------------------
$knownPlaceholders = @("Your Name", "Jane Smith", "")

if (Test-Path $EnvFile) {
    Write-Host "[INFO]  Reading env file: $EnvFile" -ForegroundColor Green
    foreach ($line in Get-Content $EnvFile) {
        if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
        $key, $value = $line -split '=', 2
        $key   = $key.Trim()
        $value = $value.Trim()
        switch ($key) {
            "GIT_NAME"       { if (-not $GitName)                    { $GitName = $value } }
            "GIT_EMAIL"      { if (-not $GitEmail)                   { $GitEmail = $value } }
            "PYTHON_VERSION" { if ($PythonVersion -eq "3.13")        { $PythonVersion = $value } }
            "INSTALL_VSCODE" { if (-not $InstallVSCode -and $value -eq "true") { $InstallVSCode = $true } }
            "INSTALL_AWS_CLI"{ if (-not $InstallAwsCli -and $value -eq "true") { $InstallAwsCli = $true } }
        }
    }
}

# ---------------------------------------------------------------------------
# Interactive Git identity prompt (when not provided or still a placeholder)
# ---------------------------------------------------------------------------
if (-not $GitName -or $knownPlaceholders -contains $GitName) {
    Write-Host "`nEnter your Git identity (used for git config --global)." -ForegroundColor Cyan
    $input = Read-Host "  Full name (leave blank to skip)"
    $GitName = $input.Trim()
}

if ($GitName -and (-not $GitEmail -or $GitEmail -match '@example\.com$' -or $GitEmail -eq "")) {
    $input = Read-Host "  Email address (leave blank to skip)"
    $GitEmail = $input.Trim()
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Refresh-Path {
    $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("PATH", "User")
}

function Get-WingetVersion {
    param([string]$Id)
    $result = winget list --id $Id --source winget --accept-source-agreements 2>$null | Select-String $Id
    if ($result) {
        $cols = ($result.Line -split '\s{2,}') | Where-Object { $_ -ne '' }
        if ($cols.Count -ge 3) { return $cols[2] }
    }
    return $null
}

# ---------------------------------------------------------------------------
# Step 1 — Python (MS Store)
# ---------------------------------------------------------------------------
function Install-Python {
    Write-Host "`n[INFO]  Checking Python Install Manager (MS Store)..." -ForegroundColor Green

    $existing = winget list --id 9NQ7512CXL7T --source msstore --accept-source-agreements 2>$null | Select-String "9NQ7512CXL7T"
    if ($existing) {
        $ver = (& py --version 2>&1) -replace 'Python ', ''
        Write-Host "[SKIP]  → Python already installed ($ver)" -ForegroundColor Yellow
        Add-Summary "Python" $ver "Skipped"
        return
    }

    Write-Host "[INFO]  Installing Python $PythonVersion via MS Store..." -ForegroundColor Green
    winget install --id 9NQ7512CXL7T --source msstore --accept-package-agreements --accept-source-agreements
    Refresh-Path

    $ver = (& py --version 2>&1) -replace 'Python ', ''
    Write-Host "[INFO]  ✔ Python installed ($ver)" -ForegroundColor Green
    Add-Summary "Python" $ver "Installed"
}

# ---------------------------------------------------------------------------
# Step 2 — pip upgrade
# ---------------------------------------------------------------------------
function Update-Pip {
    Write-Host "`n[INFO]  Upgrading pip..." -ForegroundColor Green
    & py -m pip install --upgrade pip --quiet
    $ver = (& py -m pip --version 2>&1) -replace '^pip ([^\s]+).*', '$1'
    Write-Host "[INFO]  ✔ pip upgraded ($ver)" -ForegroundColor Green
    Add-Summary "pip" $ver "Updated"
}

# ---------------------------------------------------------------------------
# Step 3 — uv
# ---------------------------------------------------------------------------
function Install-Uv {
    Write-Host "`n[INFO]  Installing uv..." -ForegroundColor Green

    $uvCmd = Get-Command uv -ErrorAction SilentlyContinue
    if ($uvCmd) {
        $ver = (& uv --version 2>&1) -replace '^uv ', ''
        Write-Host "[SKIP]  → uv already installed ($ver)" -ForegroundColor Yellow
        Add-Summary "uv" $ver "Skipped"
        return
    }

    & py -m pip install uv --quiet
    Refresh-Path
    $ver = (& uv --version 2>&1) -replace '^uv ', ''
    Write-Host "[INFO]  ✔ uv installed ($ver)" -ForegroundColor Green
    Add-Summary "uv" $ver "Installed"
}

# ---------------------------------------------------------------------------
# Step 4 — Git
# ---------------------------------------------------------------------------
function Install-Git {
    Write-Host "`n[INFO]  Checking Git..." -ForegroundColor Green

    $existingVer = Get-WingetVersion "Git.Git"
    if ($existingVer) {
        Write-Host "[SKIP]  → Git already installed ($existingVer)" -ForegroundColor Yellow
        Add-Summary "Git" $existingVer "Skipped"
    } else {
        Write-Host "[INFO]  Installing Git via winget..." -ForegroundColor Green
        winget install --id Git.Git --source winget --accept-package-agreements --accept-source-agreements
        Refresh-Path
        $existingVer = (& git --version 2>&1) -replace 'git version ', ''
        Write-Host "[INFO]  ✔ Git installed ($existingVer)" -ForegroundColor Green
        Add-Summary "Git" $existingVer "Installed"
    }

    # Git global config
    if ($GitName -and $GitEmail) {
        git config --global user.name  $GitName
        git config --global user.email $GitEmail
        Write-Host "[INFO]  ✔ Git global config set ($GitName / $GitEmail)" -ForegroundColor Green
    } else {
        Write-Host "[WARN]  ! Git global config skipped — no name/email provided." -ForegroundColor DarkYellow
        Write-Host "        Run: git config --global user.name `"Your Name`"" -ForegroundColor DarkYellow
        Write-Host "             git config --global user.email `"you@example.com`"" -ForegroundColor DarkYellow
    }
}

# ---------------------------------------------------------------------------
# Step 5 — VS Code (optional)
# ---------------------------------------------------------------------------
function Install-VSCode {
    if (-not $InstallVSCode) {
        Write-Host "`n[WARN]  ! VS Code skipped (use -InstallVSCode to enable)" -ForegroundColor DarkYellow
        Add-Summary "VS Code" "—" "Skipped (flag off)"
        return
    }

    Write-Host "`n[INFO]  Checking VS Code..." -ForegroundColor Green

    $existingVer = Get-WingetVersion "Microsoft.VisualStudioCode"
    if ($existingVer) {
        Write-Host "[SKIP]  → VS Code already installed ($existingVer)" -ForegroundColor Yellow
        Add-Summary "VS Code" $existingVer "Skipped"
    } else {
        Write-Host "[INFO]  Installing VS Code via winget..." -ForegroundColor Green
        winget install --id Microsoft.VisualStudioCode --source winget --accept-package-agreements --accept-source-agreements
        Refresh-Path
        $existingVer = (& code --version 2>&1 | Select-Object -First 1)
        Write-Host "[INFO]  ✔ VS Code installed ($existingVer)" -ForegroundColor Green
        Add-Summary "VS Code" $existingVer "Installed"
    }

    # Extensions
    foreach ($ext in @("ms-python.python", "ms-python.pylance")) {
        Write-Host "[INFO]  Installing extension: $ext" -ForegroundColor Green
        & code --install-extension $ext --force 2>&1 | Out-Null
    }
    Write-Host "[INFO]  ✔ VS Code extensions installed" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Step 6 — AWS CLI (optional)
# ---------------------------------------------------------------------------
function Install-AwsCli {
    if (-not $InstallAwsCli) {
        Write-Host "`n[WARN]  ! AWS CLI skipped (use -InstallAwsCli to enable)" -ForegroundColor DarkYellow
        Add-Summary "AWS CLI" "—" "Skipped (flag off)"
        return
    }

    Write-Host "`n[INFO]  Checking AWS CLI..." -ForegroundColor Green

    $awsCmd = Get-Command aws -ErrorAction SilentlyContinue
    if ($awsCmd) {
        $ver = (& aws --version 2>&1) -replace '^aws-cli/([^\s]+).*', '$1'
        Write-Host "[SKIP]  → AWS CLI already installed ($ver)" -ForegroundColor Yellow
        Add-Summary "AWS CLI" $ver "Skipped"
        return
    }

    $msiPath = Join-Path $env:TEMP "AWSCLIV2.msi"
    Write-Host "[INFO]  Downloading AWS CLI MSI..." -ForegroundColor Green
    try {
        Invoke-WebRequest -Uri "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile $msiPath -UseBasicParsing
        Write-Host "[INFO]  Installing AWS CLI..." -ForegroundColor Green
        Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /quiet /norestart" -Wait
        Remove-Item $msiPath -Force
        Refresh-Path
        $ver = (& aws --version 2>&1) -replace '^aws-cli/([^\s]+).*', '$1'
        Write-Host "[INFO]  ✔ AWS CLI installed ($ver)" -ForegroundColor Green
        Add-Summary "AWS CLI" $ver "Installed"

        Write-Host "`n[INFO]  To configure AWS credentials, run:" -ForegroundColor Green
        Write-Host "        aws configure" -ForegroundColor Cyan
    } catch {
        Write-Host "[ERROR] ✘ AWS CLI install failed: $_" -ForegroundColor Red
        Add-Summary "AWS CLI" "—" "Failed"
    }
}

# ---------------------------------------------------------------------------
# Step 7 — Claude Code VS Code extension (interactive prompt)
# ---------------------------------------------------------------------------
function Install-ClaudeCodeExtension {
    $codeCmd = Get-Command code -ErrorAction SilentlyContinue
    if (-not $codeCmd) {
        # VS Code not installed — nothing to do
        return
    }

    Write-Host "`n[INFO]  Claude Code is an AI coding assistant for VS Code." -ForegroundColor Green
    Write-Host "        Extension: anthropic.claude-code" -ForegroundColor Cyan
    $answer = Read-Host "        Install Claude Code extension? [y/N]"

    if ($answer -match '^[Yy]$') {
        Write-Host "[INFO]  Installing Claude Code extension..." -ForegroundColor Green
        & code --install-extension anthropic.claude-code --force 2>&1 | Out-Null
        Write-Host "[INFO]  ✔ Claude Code extension installed" -ForegroundColor Green
        Add-Summary "Claude Code (ext)" "latest" "Installed"
    } else {
        Write-Host "[SKIP]  → Claude Code extension skipped" -ForegroundColor Yellow
        Add-Summary "Claude Code (ext)" "—" "Skipped"
    }
}

# ---------------------------------------------------------------------------
# Summary table
# ---------------------------------------------------------------------------
function Show-Summary {
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "  Setup Complete — Summary" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    $summary | Format-Table -AutoSize | Out-String | Write-Host
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
Install-Python
Update-Pip
Install-Uv
Install-Git
Install-VSCode
Install-AwsCli
Install-ClaudeCodeExtension
Show-Summary
