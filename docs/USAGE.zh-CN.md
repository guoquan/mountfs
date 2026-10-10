# mouNTFS 使用与故障说明

[English](USAGE.en.md) · **简体中文** · [项目介绍](../README.zh-CN.md)

mouNTFS 是免费开源的 macOS 菜单栏工具，调用 macFUSE 和 ntfs-3g，让外置 NTFS 分区获得读写访问。保留磁盘原有格式，从菜单栏启用写入，继续在 Finder 中使用。它不会在插盘后自动改成可写，也不会格式化磁盘。

当前版本为 **0.3.4 开发版**，尚未公证发布。按下方步骤启用写入即可，无需配置 Settings 中的实验授权选项。后续授权体验与功能安排见 [ROADMAP](../ROADMAP.md)。

## 安装与更新

需要 macOS 13 或以上，以及单独安装的 Homebrew、macFUSE 和 ntfs-3g-mac：

```bash
brew install --cask macfuse
brew install gromgit/fuse/ntfs-3g-mac
```

按 [macFUSE 官方指南](https://github.com/macfuse/macfuse/wiki/Getting-Started)完成与你的系统对应的批准和重启。默认内核后端可能涉及系统扩展批准；Apple Silicon 上可能需要在恢复模式调整启动安全策略。应用不会自动修改这些设置。FSKit 是实验选项，尚未做真实磁盘验证。

从 [GitHub Actions](https://github.com/guoquan/mountfs/actions)选择所需提交的成功构建，下载对应 development-app artifact。外层 artifact 压缩包内还包含版本化下载包，例如 `mouNTFS-0.3.4-dev-arm64.zip`，继续解压得到应用。

- 下载包带版本号，便于区分构建。
- 应用始终叫 **mouNTFS.app**，便于覆盖安装。
- 更新前退出旧应用，将新应用覆盖到 `/Applications/mouNTFS.app`，再从那里打开。
- 菜单顶部显示应用版本。当前下载包使用 ad-hoc 签名，不能当作已公证的正式发行版。

## 启用写入与弹出

![原生菜单显示只读示例磁盘](images/menu-readonly.png)

*实际界面截图，使用示例磁盘数据；生成时未执行磁盘操作。*

1. 插入外置 NTFS 磁盘，点菜单栏的 mouNTFS 图标。
2. 核对分区名称和状态，点 **Enable Write Access…**。
3. 确认操作，按 macOS 授权窗口要求完成管理员授权。
4. 等待写入验证完成。成功后默认打开 Finder；可在 Settings 中关闭这个选项。
5. 使用结束后关闭占用磁盘的文件，再点 **Safely Eject…**。确认框说明的是整块物理磁盘弹出，包括其他分区。

操作中显示旋转状态，成功时不会弹出日志窗口。需要查看记录时，进入 **Diagnostics → Show Last Operation…**。应用按约五秒的间隔刷新，也响应挂载和卸载通知；插盘后只更新列表，不自动挂载。

macOS 会在需要时请求管理员授权，提示次数可能因系统而异。应用不保存密码。

## 挂载需要的权限

| 权限 | 用途 | 当前建议 |
|---|---|---|
| 管理员授权 | 执行需要提权的挂载等操作 | 按系统窗口授权；它不等于磁盘隐私权限 |
| Full Disk Access（完全磁盘访问权限） | 允许相关可执行文件访问受 macOS 隐私控制的数据/设备 | 出现设备访问拒绝时，核对实际 ntfs-3g 路径 |

当前构建会执行受保护的 ntfs-3g 副本。若 macOS 拒绝设备访问，打开 **Diagnostics → Show Last Operation…**，找到 **Protected NTFS driver:**，在 **System Settings → Privacy & Security → Full Disk Access** 中添加该行所示的可执行文件。文件选择窗口中可按 Command-Shift-G 粘贴路径。驱动及其依赖未变化时，路径保持一致；更新驱动后可能需要给新的副本授权。应用不能直接确认 macOS 是否已经授予权限。

安装诊断列出的是 Homebrew 源路径，通常为 `/opt/homebrew/bin/ntfs-3g` 或 `/usr/local/bin/ntfs-3g`。给源文件的权限不会自动覆盖操作日志中所示的受保护副本。

## 按错误定位

| 错误或现象 | 处理方向 |
|---|---|
| 插盘后没有分区 | 打开 **Show Disk Scan Report…**，看排除原因。整盘、内部盘和非 NTFS 分区不会作为挂载目标 |
| `DiskUUID=missing; VolumeUUID=missing` | 缺 UUID 不必格式化；应用可通过 IOMedia 连接身份识别分区。身份仍无法确认时会停止操作 |
| `Error opening '/dev/disk…': Operation not permitted` | 优先检查实际 ntfs-3g 的完全磁盘权限。后面附带的 unsafe-state 提示不能单独证明 Windows 休眠 |
| `Unsupported macOS Version` | 按 macFUSE 官方说明升级到兼容版本，完成批准并重启 |
| 挂载返回成功，但写入验证失败 | 查看 Show Details 中设备、挂载路径、只读标记和写入探测错误；驱动返回成功不代表实际可写 |
| 明确的休眠或不干净 NTFS 状态 | 回 Windows 完整关机或修复；应用不强制写入，不删除休眠文件 |
| 卸载提示忙碌 | 关闭占用磁盘的程序后再尝试；应用不强制卸载 |

失败后应用尽力将同一个分区恢复为 macOS 只读挂载。如果磁盘已拔出或身份发生变化，不会对替换设备执行恢复。恢复也可能被忙碌、取消授权或系统错误阻止；检查操作日志及磁盘工具。不要把“尝试恢复”理解为无条件成功。

## 报告问题时提供什么

打开 Show Details 或 Diagnostics，复制：

- 应用版本、macOS、架构、驱动路径和所选后端。
- 最近操作日志，尤其是第一条具体错误与写入验证状态。
- 只读磁盘扫描报告和安装诊断。

报告可能包含卷名、路径或用户名，发出前检查并遮去不必要的个人信息。扫描报告中的 `disk4s1` 等编号会变，不要按旧编号执行磁盘命令。更完整的已测/未测边界见 [VALIDATION.md](VALIDATION.md)。
