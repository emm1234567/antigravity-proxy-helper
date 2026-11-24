# Antigravity Proxy Helper

一个面向 **Windows 平台（暂时） Google Antigravity 桌面端** 的开源插件与静默启动工具：

- **自动检测本地 HTTP / 混合代理端口**：兼容 Clash、Mihomo / Clash Verge、v2rayN、sing-box、NekoBox、Hiddify、FlClash、Karing、Shadowsocks、iKuuuVPN 等常见代理客户端，无需手动写死端口。
- **仅对反重力进程树生效**：启动时仅向 `Antigravity.exe` 及其子进程（`language_server.exe`、终端/MCP 等）注入进程级代理环境变量与 Chromium `--proxy-server` 参数，**不修改 Windows 系统代理、不改全局环境变量、不影响其他任何软件**。
- **更新覆盖自动自愈**：内置 Antigravity 原生 `SessionStart` Hook，发现客户端自动更新覆盖桌面/开始菜单快捷方式后自动重新绑定；同时提供可选的 Windows 登录自检计划任务。
- **静默无黑框 + 完整备份与一键还原**：保留原生应用图标，安装前自动备份原始快捷方式，随时可一键恢复。

---

## 工作原理

### 1. 四层自动端口探测 + 本地 HTTP 握手校验
每次启动 Antigravity 时，`scripts/detect-proxy.ps1` 按以下顺序自动确定可用代理端口：

1. **缓存极速校验（< 20ms）**：先校验上次成功的端口是否仍在监听且响应正常，正常即秒启。
2. **手动配置优先（可选）**：若用户在 `%USERPROFILE%\.gemini\antigravity-proxy-helper\config.json` 指定了固定端口或直连模式，优先遵循用户配置。
3. **运行中代理进程反查**：扫描正在运行的常见代理进程（支持服务/高权限内核进程），检查其监听的本地端口，即使**关闭了 Windows 系统代理**也能准确发现。
4. **只读参考系统代理 + 常见端口兜底**：只读参考 `Internet Settings\ProxyServer` 及常见代理端口（`7890`、`7897`、`10809`、`10808`、`2080`、`20171`、`1081`、`4780` 等）。
5. **纯本地 HTTP 握手探针**：对候选端口发送不访问外网、不触发 DNS 的纯本地探针，自动排除纯 SOCKS5 端口、DNS 端口（`53`/`1053`）及 Clash 控制面板端口（`9090` 等）。
6. **无代理安全降级**：若当前未运行任何代理软件，则直接启动原版 `Antigravity.exe`，不会注入失效代理。

### 2. 快捷方式更新自愈机制
- **默认机制（零后台常驻）**：通过 `hooks.json` 注册 `SessionStart` 钩子。Antigravity 自动更新覆盖快捷方式后，下次打开任意新对话时 `scripts/session-guard.ps1` 会自动检测并静默修复桌面、开始菜单（及已固定到任务栏）的快捷方式。
- **可选增强（`-EnableLogonGuard`）**：安装时可附加此参数，注册一个用户级（无需管理员权限）的 Windows 登录计划任务，在登录系统时额外检查一次快捷方式。

---

## 快速安装

### 方式 A：作为 Antigravity 插件安装（推荐，支持更新自动自愈）

克隆或下载本仓库后，在 PowerShell 中运行：

```powershell
git clone https://github.com/emm1234567/antigravity-proxy-helper
cd antigravity-proxy-helper
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -InstallAsPlugin
```

如需同时开启 Windows 登录自检（可选）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -InstallAsPlugin -EnableLogonGuard
```
登录自检：
在 install.ps1 提供可选参数 -EnableLogonGuard，注册一个用户级（无需管理员权限）的 Windows 计划任务，仅在用户登录系统时跑一次 repair-shortcuts.ps1 后立刻退出。
这样哪怕刚更新完、还没开新对话，下次登录系统也会自动修好快捷方式。  

安装完成后，**完全退出并从桌面或开始菜单重新打开 Antigravity** 即可生效。

### 方式 B：直接从当前仓库目录启用（不复制到插件目录）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

---

## 验证是否生效

1. **测试自动端口探测**：
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\detect-proxy.ps1 -NoCache
   ```
2. **模拟启动检查（不实际弹窗）**：
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\launch.ps1 -DryRun -NoCache
   ```
3. **重启 Antigravity 后检查进程参数**：
   ```powershell
   Get-CimInstance Win32_Process -Filter "Name='Antigravity.exe'" |
     Where-Object { $_.CommandLine -notmatch '--type=' } |
     Select-Object ProcessId, CommandLine | Format-List
   ```
   若命令行包含 `--proxy-server="http://127.0.0.1:<端口>"`，说明已生效。

---

## 可选自定义配置

默认无需任何配置文件。若需固定端口、添加小众代理进程名或临时直连，可将 [config.example.json](config.example.json) 复制为：

```text
%USERPROFILE%\.gemini\antigravity-proxy-helper\config.json
```

常用字段说明：
- `mode`：`"auto"`（默认自动探测）/ `"manual"`（手动指定 `host` + `port`）/ `"direct"`（不走代理直连）
- `port`：`mode` 为 `"manual"` 时使用的端口号（如 `7897`）
- `autoRepairOnSessionStart`：是否启用 `SessionStart` 钩子自动修复快捷方式（默认 `true`）
- `extraProcessPatterns`：追加自定义代理进程名关键词数组
- `extraCandidatePorts`：追加优先扫描的端口号数组

运行日志位于：`%USERPROFILE%\.gemini\antigravity-proxy-helper\logs\launcher.log`。

---

## 卸载与一键恢复

在 PowerShell 中运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1
```

若同时清理缓存/日志目录和已安装的插件副本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\uninstall.ps1 -PurgeState -RemovePluginCopy
```

执行后，桌面与开始菜单快捷方式会恢复为原始的 `Antigravity.exe` 指向。

---

## 目录结构

```text
antigravity-proxy-helper/
├── plugin.json                # Antigravity 插件清单
├── hooks.json                 # SessionStart 自愈钩子配置
├── assets/logo.svg            # 插件图标
├── skills/proxy-helper/
│   └── SKILL.md               # Agent 诊断与维护技能
├── scripts/
│   ├── common.ps1             # 公共路径、配置与日志函数
│   ├── detect-proxy.ps1       # 4 层自动端口探测与 HTTP 校验
│   ├── launch.ps1             # 进程级代理注入与启动主逻辑
│   ├── launch-silent.vbs      # 无黑框静默启动包装器
│   ├── repair-shortcuts.ps1   # 快捷方式备份、绑定、自检与还原
│   ├── session-guard.ps1      # SessionStart Hook 入口
│   ├── install.ps1            # 一键安装脚本
│   └── uninstall.ps1          # 一键还原与卸载脚本
├── config.example.json        # 可选用户配置示例
├── LICENSE                    # MIT 协议
└── README.md
```

## License

[MIT](LICENSE)
