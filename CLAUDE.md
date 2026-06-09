# Claude Instructions

This is a **minimalist Windows 11 Python dotfiles** project — a single PowerShell script (`setup.ps1`) that bootstraps a clean Python development environment from scratch using only official package sources.

---

## Project Goals

- Get a freshly installed Windows 11 machine ready for Python development in one script run
- Zero bloat: no WSL, no containers, no project scaffolding — global toolchain only
- Every package comes from its official source (MS Store, winget official feed, PyPI)
- Script must be safe to re-run on an already configured machine (idempotent)

---

## Repo Structure

```
setup.ps1          # Main bootstrap script (PowerShell)
git-config.env     # Optional: Git identity and install flags
CLAUDE.md          # This file
README.md          # Usage instructions for end users
```

---

## What the Script Installs

Installs run in this order. Do not reorder without a clear reason.

| Step | Tool | Source | Notes |
|------|------|--------|-------|
| 1 | Python Install Manager | MS Store `9NQ7512CXL7T` | Official PSF build; installs `py` launcher |
| 2 | pip (upgrade) | bundled with Python | `py -m pip install --upgrade pip` |
| 3 | uv | PyPI | `py -m pip install uv` — global package manager |
| 4 | Git | winget `Git.Git` | PATH refreshed in-session after install |
| 5 | VS Code *(optional)* | winget `Microsoft.VisualStudioCode` | Only when `-InstallVSCode` flag is set |
| 6 | AWS CLI *(optional)* | Official MSI `https://awscli.amazonaws.com/AWSCLIV2.msi` | Only when `-InstallAwsCli` flag is set |

**Never use pip or winget for AWS CLI.** Always use the official MSI installer.

---

## Configuration: Parameters and env File

The script accepts configuration two ways. Parameters take precedence over the env file.

**Parameters:**

```powershell
.\setup.ps1 `
  -GitName "Jane Smith" `
  -GitEmail "jane@example.com" `
  -PythonVersion "3.13" `
  -InstallVSCode `
  -InstallAwsCli
```

**`git-config.env` file** (place next to `setup.ps1`):

```env
GIT_NAME=Jane Smith
GIT_EMAIL=jane@example.com
PYTHON_VERSION=3.13
INSTALL_VSCODE=false
INSTALL_AWS_CLI=false
```

If neither is provided, all install steps still run — only the Git global config step is skipped.

### Full Parameter Reference

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-GitName` | string | env file or skip | `git config user.name` |
| `-GitEmail` | string | env file or skip | `git config user.email` |
| `-PythonVersion` | string | `3.13` | Python version to install |
| `-InstallVSCode` | switch | false | Install VS Code and extensions |
| `-InstallAwsCli` | switch | false | Install AWS CLI via official MSI |
| `-EnvFile` | string | `.\git-config.env` | Path to env config file |

---

## Git Global Config Applied

```powershell
git config --global user.name  "<GIT_NAME>"
git config --global user.email "<GIT_EMAIL>"
```

---

## VS Code Extensions Installed

| Extension ID | Purpose |
|-------------|---------|
| `ms-python.python` | Official Python support |
| `ms-python.pylance` | Type inference and IntelliSense |

VS Code and its extensions are only installed when `-InstallVSCode` is set. Extensions are installed via `code --install-extension` with `--force` so re-runs always leave them at the latest version.

---

## Idempotency Rules

The script must be safe to run multiple times on the same machine.

- **winget packages:** check with `winget list --id <id>` before installing; skip and print current version if already present
- **AWS CLI:** check with `Get-Command aws -ErrorAction SilentlyContinue`; skip download and MSI run if already present
- **Git config:** always overwrite — re-running is an explicit reconfigure
- **VS Code extensions:** use `--force`; no harm in re-running

---

## Logging Convention

Use consistent prefixes and PowerShell color output throughout:

```
[INFO]  ✔ Git installed (2.45.0)           # Green      — Write-Host ... -ForegroundColor Green
[SKIP]  → Python already installed (3.13)  # Yellow     — Write-Host ... -ForegroundColor Yellow
[WARN]  ! VS Code not installed (flag off)  # DarkYellow
[ERROR] ✘ AWS CLI install failed            # Red        — Write-Host ... -ForegroundColor Red
```

End the script with a summary table showing every tool, its installed version, and its status (Installed / Updated / Skipped / Failed).

---

## Hard Rules — Do Not Violate

- **Official sources only.** No third-party mirrors, no Chocolatey, no Scoop.
- **No WSL.** No container runtimes. This script is global Windows toolchain only.
- **No project scaffolding.** No `pyproject.toml` generation, no virtual env creation, no pre-commit setup. Those belong in project-level tooling.
- **No credential automation.** AWS Access Keys must never be written by this script. Print `aws configure` instructions only.
- **MS Store packages use `--source msstore` explicitly** to avoid winget resolving to a different source.
- **Python version is parameterized.** Never hardcode `3.13` inside script logic; always read from `-PythonVersion` with `3.13` as the default.

---

## Coding Style (PowerShell)

- Use `#Requires -RunAsAdministrator` at the top, or handle UAC elevation via `Start-Process` with `-Verb RunAs`
- Wrap each install step in a clearly named function, e.g. `Install-Git`, `Install-VSCode`
- Refresh PATH in-session after each winget install — do not ask the user to restart
- Prefer `$PSScriptRoot` for resolving the env file path relative to the script
- Keep the script a single file — no dot-sourcing external helpers
