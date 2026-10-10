# mouNTFS 使用与故障说明

mouNTFS 是 macOS 菜单栏工具，调用 macFUSE 和 ntfs-3g，让外置 NTFS 分区获得读写访问。它不会在插盘后自动改成可写，也不会格式化磁盘。

当前版本为 **0.3.4 开发版**，尚未公证发布。普通挂载流程已有一次有限的真实使用反馈；不能据此保证所有磁盘和系统都兼容。权限 helper 和 Touch ID 属于实验功能：目前测试机上的 helper 仍启动失败，签名排查暂缓。**日常使用先走普通挂载，不必启用 helper。**

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

## 普通挂载流程

1. 插入外置 NTFS 磁盘，点菜单栏的 mouNTFS 图标。
2. 核对分区名称和状态，点 **Enable Write Access…**。
3. 确认操作，按 macOS 授权窗口要求完成管理员授权。
4. 等待写入验证完成。成功后默认打开 Finder；可在 Settings 中关闭这个选项。
5. 使用结束后关闭占用磁盘的文件，再点 **Safely Eject…**。确认框说明的是整块物理磁盘弹出，包括其他分区。

操作中显示旋转状态，成功时不会弹出日志窗口。需要查看记录时，进入 **Diagnostics → Show Last Operation…**。应用按约五秒的间隔刷新，也响应挂载和卸载通知；插盘后只更新列表，不自动挂载。

普通流程使用有时间限制的授权会话，尝试复用授权宿主；系统仍决定是否要求密码，不能保证每次只弹一次。应用不保存密码或授权令牌。若 helper 未准备好，普通流程仍可使用；已开始的 helper 操作失败后不会自动换一种授权方式重复操作磁盘。

## 三类权限不要混在一起

| 权限 | 用途 | 当前建议 |
|---|---|---|
| 管理员授权 | 执行需要提权的挂载等操作 | 按系统窗口授权；它不等于磁盘隐私权限 |
| Full Disk Access（完全磁盘访问权限） | 允许相关可执行文件访问受 macOS 隐私控制的数据/设备 | 出现设备访问拒绝时，核对实际 ntfs-3g 路径 |
| Allow in the Background（后台运行批准） | 允许可选 helper 作为系统后台服务注册和运行 | helper 测试才涉及；批准不保证服务能启动 |

已报告的可用环境中，给 **ntfs-3g** 完全磁盘权限即可工作，即使关闭 mouNTFS 的该权限也可以。常见路径为：

```text
/opt/homebrew/bin/ntfs-3g
/usr/local/bin/ntfs-3g
```

在 **System Settings → Privacy & Security → Full Disk Access** 中按实际路径添加驱动。安装诊断可显示驱动路径；应用不能直接确认系统是否已经授予该权限。上述反馈来自一个环境，不代表所有系统都只需同一项权限。

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
| `Helper status check timed out` | helper 未响应；这不是磁盘权限不足的证明 |
| `OS_REASON_CODESIGNING` | 系统因签名相关检查终止了 helper；停止反复授全盘权限或 Repair，先走普通挂载 |

失败后应用尽力将同一个分区恢复为 macOS 只读挂载。如果磁盘已拔出或身份发生变化，不会对替换设备执行恢复。恢复也可能被忙碌、取消授权或系统错误阻止；检查操作日志及磁盘工具。不要把“尝试恢复”理解为无条件成功。

## helper 和 Touch ID：当前暂停验证

helper 的目标是一次完成后台服务批准及受保护驱动设置，之后由受限的 root 服务处理挂载，减少逐条命令的管理员密码请求。Touch ID 只在 helper 已准备好、设备支持生物识别时确认用户意图；它不是 helper 安装凭据，也不授予完全磁盘权限。

**当前实测没有完成这一流程。** 0.3.4 的 Repair 出现 `SMAppServiceErrorDomain / 1`，随后服务依然以 `OS_REASON_CODESIGNING` 退出。显式启动约束已被系统读取，但未解决问题。后台开关、重复 Repair 和重授磁盘权限都不能作为已验证的修复办法。

测试机只有 Command Line Tools，且 `security find-identity -v -p codesigning` 返回 `0 valid identities found`，签名排查暂缓。Command Line Tools 仍足以构建普通 ad-hoc 开发版。以后继续排查时，优先用同一个 Apple 签发的身份重新构建应用及 helper；目前没有证据保证换签名即可解决全部问题。

不能直接重签下载好的应用：XPC 双方绑定了构建时签名哈希，需要通过构建脚本重新生成。具体开发步骤和架构见 [AUTHORIZATION.md](AUTHORIZATION.md)。

## 报告问题时提供什么

打开 Show Details 或 Diagnostics，复制：

- 应用版本、macOS、架构、驱动路径和所选后端。
- 最近操作日志，尤其是第一条具体错误与写入验证状态。
- 只读磁盘扫描报告和安装诊断。
- helper 问题另附启动状态、注册错误和签名信息。

报告可能包含卷名、路径或用户名，发出前检查并遮去不必要的个人信息。扫描报告中的 `disk4s1` 等编号会变，不要按旧编号执行磁盘命令。更完整的已测/未测边界见 [VALIDATION.md](VALIDATION.md)。
