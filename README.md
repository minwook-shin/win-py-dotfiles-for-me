# win-py-dotfiles

One-script bootstrap for a minimal Python development environment on a clean Windows 11 machine.

After running this script you can immediately `git clone` any project and open it in VS Code.

---

## What gets installed

| Step | Tool | Source |
|------|------|--------|
| 1 | Python (with `py` launcher) | MS Store |
| 2 | pip (latest) | bundled with Python |
| 3 | uv (fast global package manager) | PyPI |
| 4 | Git | winget |
| 5 | VS Code + Python extensions *(optional)* | winget |
| 6 | AWS CLI *(optional)* | Official MSI |

The script is **idempotent** — safe to re-run on an already configured machine.

---

## Quick start

### 1. Clone this repo

Open **PowerShell as Administrator** and run:

```powershell
git clone https://github.com/minwook-shin/win-py-dotfiles-for-me.git
cd win-py-dotfiles-for-me
```

> If Git is not yet installed, download and run the installer from <https://git-scm.com/download/win>, then open a new PowerShell window.

### 2. Edit `git-config.env`

```env
GIT_NAME=Jane Smith
GIT_EMAIL=jane@example.com
PYTHON_VERSION=3.13
INSTALL_VSCODE=false
INSTALL_AWS_CLI=false
```

Set `INSTALL_VSCODE=true` if you want VS Code installed automatically.

### 3. Run the script

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\setup.ps1
```

The script will self-elevate to Administrator if needed.

---

## Parameters

All settings in `git-config.env` can also be passed as parameters (parameters take precedence):

```powershell
.\setup.ps1 `
  -GitName "Jane Smith" `
  -GitEmail "jane@example.com" `
  -PythonVersion "3.13" `
  -InstallVSCode `
  -InstallAwsCli
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-GitName` | string | env file | `git config user.name` |
| `-GitEmail` | string | env file | `git config user.email` |
| `-PythonVersion` | string | `3.13` | Python version to install |
| `-InstallVSCode` | switch | false | Install VS Code and Python/Pylance extensions |
| `-InstallAwsCli` | switch | false | Install AWS CLI via official MSI |
| `-EnvFile` | string | `.\git-config.env` | Path to the env config file |

---

## After setup — clone a project and start coding

```powershell
git clone https://github.com/you/your-project.git
cd your-project
code .
```

Inside VS Code, open the integrated terminal and create a virtual environment with uv:

```powershell
uv venv
.venv\Scripts\activate
uv pip install -r requirements.txt   # or: uv sync
```

---

## AWS credentials

The script **never writes AWS credentials**. After setup, run:

```powershell
aws configure
```

---

## Requirements

- Windows 11
- PowerShell 7+ (pwsh) recommended; Windows PowerShell 5.1 works too
- Internet connection
- Administrator rights (the script self-elevates)
