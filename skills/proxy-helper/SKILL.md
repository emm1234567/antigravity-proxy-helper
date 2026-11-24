---
name: proxy-helper
description: Diagnose, configure, install, repair, or uninstall Windows per-app auto-proxy launching for Antigravity without modifying system proxy settings. Use when the user asks about Antigravity proxy issues, proxy port auto-detection, shortcut repair after updates, or rolling back proxy launcher changes.
---

# Antigravity Proxy Helper (Windows)

This skill manages the **Antigravity Proxy Helper** scripts bundled with this plugin. All scripts live in the sibling `../../scripts/` directory relative to this `SKILL.md` file.

## Design Principles

- **Per-app only**: Never modify Windows system proxy (`Internet Settings`), global/user environment variables, or other applications' settings.
- **Confirm before writing**: Before modifying shortcuts, creating scheduled tasks, or editing `%USERPROFILE%\.gemini\antigravity-proxy-helper\config.json`, show the user what will change and ask for confirmation unless they explicitly requested immediate execution.
- **No hardcoded personal paths or ports**: Rely on automatic detection unless the user explicitly wants a manual override.

## Common Workflows

Resolve `<plugin_root>` to the parent directory of `skills/proxy-helper/` (two levels up from this `SKILL.md`).

### 1. Diagnose Proxy & Shortcut Status (Read-Only)

Run both read-only checks:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<plugin_root>\scripts\detect-proxy.ps1" -NoCache -Json
powershell -NoProfile -ExecutionPolicy Bypass -File "<plugin_root>\scripts\repair-shortcuts.ps1" -CheckOnly -Json
```

Summarize for the user:
- Detected local HTTP/mixed proxy URL, detection layer (`manual_config` / `cache` / `process` / `system_proxy_registry` / `common_port_scan` / `none`), and matched process name if any.
- Status of Desktop, Start Menu, and Taskbar shortcuts (`ok` vs `needs_repair`).

### 2. Install or Repair Shortcuts

After confirming with the user:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<plugin_root>\scripts\install.ps1"
```

Optional flags:
- `-EnableLogonGuard`: Also registers a user-level Windows logon Scheduled Task (`AntigravityProxyHelperLogonGuard`) to re-bind shortcuts at logon if an update overwrites them.
- `-Force`: Forces re-writing shortcuts even if already bound.

### 3. Dry-Run Launch Check

Verify what `launch.ps1` will pass to `Antigravity.exe` without spawning a new window:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<plugin_root>\scripts\launch.ps1" -DryRun -NoCache
```

### 4. Manual Port Override or Direct Mode

State and optional configuration live in `%USERPROFILE%\.gemini\antigravity-proxy-helper\config.json` (see `<plugin_root>\config.example.json` for schema):
- `"mode": "auto"` (default): Automatic 4-layer detection.
- `"mode": "manual"` + `"port": 7897`: Pin a specific local HTTP/mixed port.
- `"mode": "direct"`: Bypass proxy injection while keeping the shortcut intact.
- `"autoRepairOnSessionStart": false`: Disable automatic shortcut repair in the `SessionStart` hook.

### 5. Uninstall / Rollback

Restore original shortcuts from backups and remove any optional logon task:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<plugin_root>\scripts\uninstall.ps1"
```

Add `-PurgeState` to also remove `%USERPROFILE%\.gemini\antigravity-proxy-helper`.
