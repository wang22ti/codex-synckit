# Codex SyncKit

简体中文 | [English](README.md)

**通过 OneDrive，把同一套 Codex 工作环境带到多台 Windows 电脑；不需要
Git，不需要手工创建目录链接，也不需要自己搬运隐藏文件夹。**

Codex SyncKit 会把适合跨电脑共享的 Codex 数据导出到 OneDrive 中的私有目录，
安全地连接每台电脑，并安装一个托管的 `ChatGPT` 开始菜单快捷方式。完成一次性
安装后，日常使用只需从这个快捷方式打开 ChatGPT，不需要记忆或执行日常
PowerShell 命令。

## 为什么使用它

- **专门理解 Codex：** 能识别技能、Hooks、全局指导、记忆、项目、自动化、
  会话以及桌面侧边栏状态。
- **普通用户不需要 Git：** 下载 ZIP 后运行一条 PowerShell 安装命令即可。
- **默认注重安全：** 替换前备份原数据，重要复制使用 SHA-256 校验，遇到冲突
  先停止，桌面状态同步失败时不会继续启动。
- **私密的设备状态留在本机：** 凭据、命令审批、缓存、日志、本地偏好和 Codex
  SQLite 数据库不会被同步。
- **统一的启动方式：** 托管快捷方式会协调 ChatGPT 启动前需要拉取、关闭后需要
  推送的状态。

## 它是怎样工作的

1. 引导安装器在 OneDrive 中创建一个私有 `CodexKit` 目录，保存选定的共享
   Codex 数据。
2. 安装器通过经过验证的目录链接、Hooks 和托管快捷方式，把每台 Windows 电脑
   连接到这套共享数据。
3. OneDrive 负责在电脑之间传输文件；Codex SyncKit 负责 Codex 专用的目录结构、
   安装、校验、备份和冲突保护。

Codex SyncKit 不会取代 OneDrive，而是在 OneDrive 之上补齐 Codex 同步所需的
专用逻辑。

## 可以同步什么

| 类别 | 默认状态 | 作用 |
| --- | --- | --- |
| 技能、Hooks 和全局指导 | 开启 | 让每台电脑拥有相同的 Codex 能力与指令 |
| 全局记忆 | 推荐安装时开启 | 共享长期上下文，但不复制各电脑自己的维护状态 |
| 环境与插件清单 | 开启 | 记录各电脑的差异；只报告插件，不复制插件缓存 |
| Codex 项目 | 可选 | 让多台电脑通过正常的 Windows 文档目录访问同一项目工作区 |
| Codex 自动化 | 可选 | 共享自动化定义；同一个计划任务只应由一台指定电脑运行 |
| 会话历史 | 开启 | 让另一台电脑重新打开并继续同一个 Codex 任务；其中可能包含完整提示词和回答 |
| 侧边栏与项目组织 | 开启 | 同步任务标题、置顶、项目分组、排序和工作区提示 |
| 凭据、审批规则、缓存、日志、本地偏好、`state_5.sqlite` | 永不同步 | 为了安全和稳定，这些内容始终保留在本机 |

“会话历史”和“侧边栏与项目组织”属于私密数据，因为其中可能包含对话正文、
项目名称和本地路径。但跨电脑继续原来的 Codex 任务、保留相同的任务组织，正是
Codex SyncKit 的核心用途，因此它们默认开启。请保持生成的 `CodexKit` 目录为
私有目录，并阅读[隐私说明](docs/PRIVACY.md)了解数据边界。

## 与其他方案对比

| 方案 | 主要用途 | 是否理解 Codex 结构 | 用户需要做什么 | 更适合 |
| --- | --- | --- | --- | --- |
| **Codex SyncKit** | 借助 OneDrive，让多台 Windows 电脑拥有可直接使用的同一套 Codex 环境 | 是 | 运行一次安装器；不需要 Git 或手工链接 | 希望每台电脑上的 Codex 都像同一个工作区的用户 |
| 单独使用 [OneDrive](https://support.microsoft.com/en-us/onedrive/sync-your-computer-s-files-and-folders-with-onedrive) | 云端文件和文件夹同步 | 否 | 自己判断隐藏数据、复制范围以及怎样让 Codex 使用这些文件 | 普通文档和文件夹 |
| [Syncthing](https://docs.syncthing.net/intro/getting-started.html) | 在配对设备之间直接同步文件夹 | 否 | 每台设备安装、交换设备 ID、选择同步文件夹 | 不希望依赖中心云目录的一般文件同步 |
| [chezmoi](https://www.chezmoi.io/what-does-chezmoi-do/) | 跨机器声明式管理 dotfiles | 否 | 理解源状态、模板和偏 Git 的工作流 | 管理跨平台 Shell 与应用配置的技术用户 |
| [Git](https://git-scm.com/about) 加自定义脚本 | 完全由用户控制的版本化配置 | 只理解你自己实现的部分 | 自己设计仓库、排除规则、目录链接、迁移与冲突处理 | 需要完全自定义和完整历史的开发者 |

通用工具覆盖面更广，可能更适合一般文件或跨平台 dotfiles。Codex SyncKit 的范围
更窄：它预先处理了 Codex 特有的路径、安装方式和安全规则，用户不必自己设计整套
系统。

## 系统要求

- Windows 10 或 Windows 11
- Windows PowerShell 5.1 或更高版本
- OneDrive
- Codex/ChatGPT 桌面应用或 Codex CLI
- Node.js，用于桌面状态和任务目录辅助工具

安装和日常使用不需要 Git。

## 从 Release ZIP 安装

1. 下载最新 Release ZIP 及其 `.sha256` 文件。
2. 校验 SHA-256 并解压 ZIP。
3. 在解压目录中打开 PowerShell。
4. 运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-CodexSyncKit.ps1 -Recommended
```

该命令会以兼容 ID `codexkit-sync` 安装随包附带的技能，导出 OneDrive 私有包，
应用推荐链接，并创建托管的 `ChatGPT` 快捷方式。会话和桌面状态同步默认开启。
只有在明确不想同步相应内容时，才需要添加
`-ExcludeSessions` 或 `-ExcludeDesktopState`。

## 日常使用与同步注意事项

日常不需要运行命令，只需从开始菜单中的托管 `ChatGPT` 快捷方式启动。

- 换到另一台电脑前，先关闭 ChatGPT，并等待 OneDrive 显示 `CodexKit` 已同步
  完成。
- 不要在两台电脑上同时操作同一个已同步会话。
- 如果启用了会话或侧边栏同步，同一时间只运行一个托管 ChatGPT，并等待关闭后的
  同步完成。
- 不要公开或分享生成的私有 `CodexKit` 目录。其中可能包含记忆、项目元数据、
  设备环境信息，以及启用后保存的完整会话历史。
- 不要手工复制或链接凭据、命令审批规则、`state_5.sqlite`、缓存或日志。
- 如果出现 OneDrive 冲突副本或旧的“其他设备正在运行”警告，应先停止操作，
  确认哪台电脑拥有最新状态。

隐私边界、恢复与移除方法见[隐私说明](docs/PRIVACY.md)、
[安全政策](SECURITY.md)和[卸载说明](docs/UNINSTALL.md)。

## 当前支持范围

Alpha 版本有意聚焦于 Windows 和 OneDrive。Codex 的内部存储结构可能随桌面应用
版本变化；遇到不受支持的布局时，工具应给出诊断并停止，而不是进行推测性修改。

欢迎参与贡献，详见 [CONTRIBUTING.md](CONTRIBUTING.md)。本项目采用
[MIT 许可证](LICENSE)。

Codex SyncKit 是独立的社区项目，与 OpenAI 不存在隶属、赞助或官方认可关系。
OpenAI、ChatGPT 和 Codex 是其各自所有者的商标。本项目不分发 OpenAI 标志。
