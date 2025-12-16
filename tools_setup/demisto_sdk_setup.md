# Demisto SDK Setup Guide

The `demisto-sdk` is the official command-line tool for developing, maintaining, and validating Cortex XSOAR content.

## 1. Prerequisites
*   **Python:** 3.8+ (Recommend management via `pyenv` or `conda`)
*   **Docker:** Required for running linting and unit tests in isolated environments.
*   **Git:** Required for version control operations.

## 2. Installation

Install via pip (in your virtual environment):
```bash
python3 -m pip install demisto-sdk
```

Verify installation:
```bash
demisto-sdk --version
```

## 3. Configuration (Optional but Recommended)

For `demisto-sdk run-playbook` or uploading content directly to your XSOAR server, export the following environment variables:

```bash
# Add to your ~/.bashrc or ~/.zshrc

# URL of your XSOAR instance
export DEMISTO_BASE_URL="https://your-xsoar-instance.com"

# API Key (Settings -> Integrations -> API Keys -> Get Your Key)
export DEMISTO_API_KEY="your-api-key-here"

# If using a self-signed cert on XSOAR
export DEMISTO_VERIFY_SSL="false"
```

## 4. Common Commands

### Validation
Checks validity of YAML files, JSON files, and general structure.
```bash
# Validate specific file
demisto-sdk validate -i Packs/MyPack/Playbooks/playbook-MyPlaybook.yml

# Validate entire pack
demisto-sdk validate -i Packs/MyPack
```

### Linting (Python)
Runs flake8, mypy, bandit, and pytest in a Docker container.
```bash
# Lint specific integration directory
demisto-sdk lint -i Packs/MyPack/Integrations/MyIntegration

# Lint everything in a pack
demisto-sdk lint -i Packs/MyPack
```

### Formatting
Automatically formats YAML and JSON files to standard XSOAR schema (fixes indentation, version numbers).
```bash
demisto-sdk format -i Packs/MyPack/Playbooks/playbook-MyPlaybook.yml
```

### Secrets Checks
Scans for potential hardcoded secrets before commit.
```bash
demisto-sdk secrets
```
