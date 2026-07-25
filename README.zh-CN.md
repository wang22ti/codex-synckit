# Codex SyncKit

简体中文 | [English](README.md)

一个非官方、本地优先的 Windows 工具包，用于将 Codex 工作环境导出到
OneDrive，并在不同电脑上安装、检查和修复该环境。

这是一个社区项目，与 OpenAI 不存在隶属、赞助或官方认可关系。OpenAI、
ChatGPT 和 Codex 是其各自所有者的商标。本项目不分发 OpenAI 标志。

## 管理内容

- Codex 和 Agents 技能
- 可移植的 Hooks 与全局指导文件
- 可选的全局记忆链接
- 各设备的环境清单
- 插件清单
- 可选的 Codex 项目和自动化任务
- 可选的会话与桌面侧边栏同步
- 使用受控 Pull/Push 同步流程的 ChatGPT 托管启动器

凭据、命令审批策略、缓存、日志以及 Codex SQLite 状态数据库会被明确排除。

## 系统要求

- Windows 10 或 Windows 11
- Windows PowerShell 5.1 或更高版本
- OneDrive
- Codex/ChatGPT 桌面应用或 Codex CLI
- Node.js，用于桌面状态和任务目录辅助工具

安装和日常使用不需要 Git。

## 从 Release ZIP 安装

1. 下载最新的 Release ZIP 及其 `.sha256` 文件。
2. 校验 SHA-256。
3. 解压 ZIP。
4. 在解压目录中打开 PowerShell。
5. 运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-CodexSyncKit.ps1 -Recommended
```

该命令会以兼容 ID `codexkit-sync` 安装随包附带的技能，在 OneDrive 中导出
一套私有 CodexKit，并应用推荐链接。默认不会启用会话或桌面状态同步。

如果只想导出而不安装链接：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-CodexSyncKit.ps1
```

如果需要指定其他目标目录：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-CodexSyncKit.ps1 `
  -DestinationRoot "D:\OneDrive\CodexKit" -Recommended
```

## 涉及私有数据的功能

会话记录和桌面状态可能包含提示词、回答、本地路径、项目名称以及粘贴过的
敏感信息，因此这些功能默认关闭。

启用它们时，必须同时提供明确的功能开关和风险确认：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-CodexSyncKit.ps1 `
  -IncludeSessions -IncludeDesktopState -AcceptPrivateDataRisk
```

不要在两台电脑上同时操作同一个已同步会话。

## 日常命令

在 OneDrive 中的私有 CodexKit 目录运行：

```powershell
.\Install-CodexKitForWindows.ps1 -Status
.\Install-CodexKitForWindows.ps1 -Repair
.\Switch-CodexMachine.cmd
```

日常启动请使用开始菜单中安装好的 `ChatGPT` 快捷方式，以执行受控的
Pull、启动和 Push 生命周期。

## 安全设计

- 替换现有目标之前会先创建备份。
- 检测到冲突时会在修改前停止。
- 重要复制操作使用 SHA-256 校验。
- 桌面状态同步采用失败关闭策略。
- 永远不会复制或链接 `state_5.sqlite`。
- 会话同步必须主动选择启用。
- 公开发布包不包含任何导出的用户数据。

启用可选状态同步之前，请阅读[隐私说明](docs/PRIVACY.md)、
[安全政策](SECURITY.md)和[卸载说明](docs/UNINSTALL.md)。

## 支持范围

首个公开版本有意聚焦于 Windows 和 OneDrive。Codex 的内部存储结构可能随
桌面应用版本变化；遇到不受支持的布局时，工具应给出诊断并停止，而不是进行
推测性修改。

## 参与贡献

请参阅 [CONTRIBUTING.md](CONTRIBUTING.md)。贡献者需要使用 Git，但终端用户
不需要。

## 许可证

采用 MIT 许可证，详见 [LICENSE](LICENSE)。
