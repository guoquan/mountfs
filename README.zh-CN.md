# *mouNT*FS

[English](README.md) · **简体中文**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Built with AI](https://img.shields.io/badge/Built--with-AI-blueviolet)](#人机协同开发)
[![Website](https://img.shields.io/badge/Website-mountfs.sh-blue)](https://mountfs.sh)

### Mac，也能写入 NTFS。

**免费开源，保留磁盘原有的 NTFS 格式。**

无需格式化。从菜单栏启用写入，继续在 Finder 中拷贝文件。mouNTFS 是管理外置 NTFS 磁盘的原生 Mac 应用，也保留独立脚本供命令行使用。

![mouNTFS：Mac 也能写入 NTFS，免费开源](docs/images/promo-hero.zh-CN.png)

*宣传图依据应用英文界面制作，使用示例磁盘数据；需单独安装驱动并完成 macOS 权限配置。*

**当前版本：0.3.4 开发版。** 需要单独安装 macFUSE 和 ntfs-3g。开发下载包使用 ad-hoc 签名，尚未公证。

[开始使用](docs/USAGE.zh-CN.md) · [下载构建](https://github.com/guoquan/mountfs/actions) · [后续计划](ROADMAP.md)

## 看看现在的应用

| 选择磁盘 | 写入已启用 |
|---|---|
| ![原生菜单显示只读示例磁盘](docs/images/menu-readonly.png) | ![原生菜单显示可写示例磁盘](docs/images/menu-writable.png) |

<details>
<summary>操作进度与诊断报告</summary>

| 操作进行中 | 可复制的操作报告 |
|---|---|
| ![原生菜单显示示例操作进度](docs/images/menu-progress.png) | ![原生诊断窗口显示示例报告](docs/images/diagnostics.png) |

</details>

截图来自实际 macOS 应用界面，使用**示例磁盘数据与示例日志**，生成截图时没有执行磁盘挂载。当前应用界面为英文。

## 你的磁盘，熟悉的使用方式

- **保留 NTFS 格式。** 使用已有外置磁盘，无需重新格式化。
- **从菜单栏启用写入。** 选择磁盘，完成授权，等待挂载完成。
- **继续在 Finder 中使用。** 写入启用后即可拷贝、编辑和整理文件；成功后默认打开 Finder。
- **用完安全弹出。** 关闭占用磁盘的文件，再从应用中弹出磁盘。

应用显示磁盘状态和操作进度，自动刷新磁盘列表，需要排查时可查看报告。插盘不会自动启用写入。首次使用需要安装兼容驱动、完成系统批准和磁盘访问权限配置。

## 快速开始

需要 macOS 13 或以上、Homebrew 和兼容的驱动：

```bash
brew install --cask macfuse
brew install gromgit/fuse/ntfs-3g-mac
```

按 [macFUSE 安装指南](https://github.com/macfuse/macfuse/wiki/Getting-Started)完成系统批准和重启。从 [Actions](https://github.com/guoquan/mountfs/actions)下载成功的 macOS 构建，解压后将 **mouNTFS.app** 放入 Applications。

1. 连接磁盘，打开 mouNTFS 菜单。
2. 点击 **Enable Write Access…**，完成 macOS 授权。
3. 等待写入验证完成；默认随后打开 Finder。
4. 关闭使用中的文件，再点 **Safely Eject…**；这会弹出整块物理磁盘。

若 macOS 拒绝设备访问，检查实际 **ntfs-3g** 可执行文件的完全磁盘权限。管理员授权是另一项权限。[使用说明](docs/USAGE.zh-CN.md)包含安装、更新与故障处理。标准使用流程不需要配置实验授权选项。

## 安全与兼容性

mouNTFS 只对外置 NTFS 分区操作，核对所选设备身份，以当前用户验证写入，并在失败时尽力将同一个卷恢复为只读挂载。它不会强制卸载、清除 Windows 休眠状态或格式化磁盘。恢复仍可能失败；操作失败时请查看诊断和磁盘工具。

普通挂载已有有限的 Apple Silicon 使用反馈；其他磁盘、系统及驱动组合仍需继续测试。已测依据和待测项目见 [验证记录](docs/VALIDATION.md)。FSKit 仍是实验选项。

## 文档导航

| 用户文档 | English | 简体中文 |
|---|---|---|
| 项目介绍 | [README](README.md) | [项目介绍](README.zh-CN.md) |
| 安装、使用与故障处理 | [Usage guide](docs/USAGE.en.md) | [使用说明](docs/USAGE.zh-CN.md) |

开发类文档统一使用英文：

- [Roadmap](ROADMAP.md)：后续阶段和完成标准。
- [Authorization architecture](docs/AUTHORIZATION.md)：权限服务、签名和 Touch ID 边界。
- [Validation record](docs/VALIDATION.md)：CI、真实 Mac 反馈和待测项目。
- [Contributing and documentation](CONTRIBUTING.md)：本机构建、检查和截图生成。

## 构建与参与

在装有 Xcode Command Line Tools 的 macOS 上，进入项目目录：

```bash
bash scripts/build-app.sh
open dist/mouNTFS.app
```

下载包带版本号，应用保持 **mouNTFS.app** 名称以便覆盖更新；替换前先退出旧应用。本开发分支尚未更新独立网站的下载入口。

## 人机协同开发

> 🤝 一场人机协同开发实验，和 AI 搭子一起做出来。
> 🤖 AI 写代码；👤 人类负责设计、审查、测试与方向。
> 🥳 从一个 Shell 脚本到原生 Mac 应用，看看这趟旅程还能走到哪里。

协作方式也是这个项目的个性：AI 写代码，人类塑造产品、审查改动，并在真实环境中测试。

最初协作者：Claude 3.5 Sonnet、GPT-4o 和 [guoquan](https://guoquan.net)。当前开发更新由 Codex 协助完成。欢迎贡献和安全审查。

MIT License © 2024–2026 Quan Guo.
