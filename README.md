# Alwaysnew — Blender 官网自动更新（Windows）

从 [download.blender.org](https://download.blender.org/release/) 检测并安装 **最新稳定版** Windows MSI，支持命令行手动更新与任务计划程序定期自动更新。

## 要求

- Windows 10 / 11
- PowerShell 5.1 或更高（Windows 自带即可）
- 能访问 `download.blender.org`
- 安装 / 静默更新时建议以 **管理员** 运行（MSI 需要提升权限）

本工具只管理官网稳定版 MSI，**不管理** Steam 版或便携 zip。

## 快速开始

在仓库目录打开 PowerShell：

```powershell
# 查看本地 / 官网版本与定时任务状态
.\blender-updater.ps1 status

# 仅检查是否有新版本（有更新时退出码为 2）
.\blender-updater.ps1 check

# 下载并静默安装官网最新稳定版（建议管理员）
.\blender-updater.ps1 update

# 注册每周日 10:00 自动更新
.\blender-updater.ps1 schedule

# 自定义星期与时间
.\blender-updater.ps1 schedule -DayOfWeek Monday -At 21:30

# 取消定时任务
.\blender-updater.ps1 unschedule
```

若执行策略拦截脚本，可先对当前进程放开：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\blender-updater.ps1 status
```

## 命令说明

| 命令 | 作用 |
|------|------|
| `check` | 对比本地与官网版本，不安装 |
| `update` | 有新版本则下载、校验 SHA256、静默安装 |
| `schedule` | 注册任务计划：`Alwaysnew-BlenderUpdater` |
| `unschedule` | 删除上述定时任务 |
| `status` | 显示本地版本、远程版本、任务状态 |

常用参数：

- `-Force`：即使版本相同也重新下载安装
- `-WhatIf`：只演练，不真正下载 / 安装 / 改任务
- `-DayOfWeek` / `-At`：仅用于 `schedule`
- `-ConfigPath`：指定配置文件路径

## 配置

复制示例配置后按需修改：

```powershell
Copy-Item .\config.example.json .\config.json
```

| 字段 | 说明 |
|------|------|
| `InstallPath` | 可选。指定已安装的 Blender 目录（含 `blender.exe`） |
| `ReleaseRootUrl` | 官网发布根目录，默认官方地址 |
| `CacheDir` / `LogDir` | 下载缓存与日志目录 |
| `Channel` | 当前仅支持 `Stable` |

日志默认写入：

`%LOCALAPPDATA%\Alwaysnew\BlenderUpdater\logs\`

## 工作方式

1. 解析 `https://download.blender.org/release/` 下最新的 `BlenderX.Y/` 目录  
2. 按本机架构选择 `windows-x64` 或 `windows-arm64` 的最新 MSI  
3. 用同目录 `.sha256` 校验文件  
4. 通过 `msiexec /i ... /qn /norestart` 静默安装  
5. `schedule` 会创建每周任务，以最高权限运行 `blender-updater.ps1 update`

用户配置目录（`%APPDATA%\Blender Foundation\Blender\`）由 Blender 自己管理，本工具不会删除。

## 退出码

| 码 | 含义 |
|----|------|
| `0` | 成功 / 已是最新 |
| `1` | 失败 |
| `2` | 仅 `check`：发现可用更新 |

## 开发校验

在已安装 PowerShell 7+ 的环境可运行语法与解析自检：

```powershell
pwsh -NoProfile -File .\tests\Validate-Updater.ps1
```
