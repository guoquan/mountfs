import AppKit
import Darwin
import MountFSCore
import MountFSPrivileged
import ServiceManagement
import LocalAuthentication
import CoreServices

let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3.4"

func helperResult(_ option: String, device: String) -> CommandResult? {
    var candidates: [String?] = [Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("mountfs-identity").path]
    // A distributed app trusts only its bundled identity client. Never execute
    // a current-directory binary when a packaged helper is missing.
    if !Bundle.main.bundlePath.hasSuffix(".app") {
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/release/MountFSIdentity").path)
    }
    guard let path = candidates.compactMap({ $0 }).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
    return runCommand(path, [option, device], mergeErrors: false)
}

func bundledHelperCommand(_ arguments: [String]) -> CommandResult {
    guard let path = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("mountfs-identity").path else {
        return CommandResult(status: 1, output: Data("Bundled helper client missing.".utf8))
    }
    return runCommand(path, arguments)
}

func currentIdentity(_ device: String) -> String? {
    guard let result = helperResult("--identity", device: device), result.status == 0 else { return nil }
    return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
}

func currentMountState(_ device: String) -> [String: Any]? {
    guard let result = helperResult("--mount-state", device: device), result.status == 0 else { return nil }
    return (try? PropertyListSerialization.propertyList(from: result.output, format: nil)) as? [String: Any]
}

struct Volume: Equatable {
    let device: String
    let mediaIdentity: String?
    let name: String
    let mountPoint: String?
    let readOnly: Bool
}

struct CommandResult {
    let status: Int32
    let output: Data
    var text: String { String(decoding: output, as: UTF8.self) }
}

private final class ErrorCapture {
    private let lock = NSLock()
    private var data = Data()
    func set(_ value: Data) { lock.lock(); data = value; lock.unlock() }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}

// All commands use Process arguments; volume names are never evaluated as code.
func runCommand(_ executable: String, _ arguments: [String], mergeErrors: Bool = true, environment: [String: String]? = nil) -> CommandResult {
    let process = Process()
    let pipe = Pipe()
    let errorPipe = Pipe()
    let errors = ErrorCapture()
    let group = DispatchGroup()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if let environment { process.environment = environment }
    process.standardOutput = pipe
    process.standardError = errorPipe
    do {
        try process.run()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errors.set(errorPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        var output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        group.wait()
        if mergeErrors || process.terminationStatus != 0 { output.append(errors.get()) }
        return CommandResult(status: process.terminationStatus, output: output)
    } catch {
        return CommandResult(status: 1, output: Data(error.localizedDescription.utf8))
    }
}

func diskDictionary(_ arguments: [String]) -> [String: Any]? {
    let result = runCommand("/usr/sbin/diskutil", arguments, mergeErrors: false)
    guard result.status == 0,
          let object = try? PropertyListSerialization.propertyList(from: result.output, format: nil)
    else { return nil }
    return object as? [String: Any]
}

struct ScanResult {
    let volumes: [Volume]
    let report: String
}

func scanVolumes(verifiedIdentities: [String: String] = [:]) -> ScanResult? {
    guard let list = diskDictionary(["list", "-plist"]), let disks = list["AllDisks"] as? [String]
    else { return nil }
    var report = ["mouNTFS \(appVersion) — read-only disk scan", "Scanned \(disks.count) disk identifiers."]
    let volumes: [Volume] = disks.compactMap { device in
        let scannedIdentity = currentIdentity(device)
        guard let info = diskDictionary(["info", "-plist", device]) else {
            report.append("\(device): cannot read or parse diskutil info")
            return nil
        }
        let externalPartition = info["Internal"] as? Bool == false && info["WholeDisk"] as? Bool == false
        let verified = externalPartition && verifiedIdentities[device] != nil && currentIdentity(device) == verifiedIdentities[device]
        let state = externalPartition && (info["FilesystemType"] as? String == "ntfs" || verified) ? currentMountState(device) : nil
        let disk = DiskMetadata(info, mountState: state, verifiedNTFS: verified)
        // Reports remain local and omit names, paths and UUIDs.
        let partitionID = (info["DiskUUID"] as? String).map { !$0.isEmpty } ?? false
        let volumeID = (info["VolumeUUID"] as? String).map { !$0.isEmpty } ?? false
        report.append("\(device): \(disk.exclusionReason); mounted=\(disk.isMounted); readOnly=\(disk.readOnly); DiskUUID=\(partitionID ? "present" : "missing"); VolumeUUID=\(volumeID ? "present" : "missing")")
        guard disk.isExternalNTFSPartition else { return nil }
        let identity = scannedIdentity != nil && currentIdentity(device) == scannedIdentity ? scannedIdentity : nil
        return Volume(device: device, mediaIdentity: identity, name: disk.name, mountPoint: disk.mountPoint, readOnly: disk.readOnly)
    }
    report.append("Included \(volumes.count) external NTFS partition(s).")
    return ScanResult(volumes: volumes, report: report.joined(separator: "\n"))
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var volumes: [Volume] = []
    private var busy = false
    private var helperReady = false
    private var helperStatus = "Not enabled"
    private let helperService = SMAppService.daemon(plistName: helperPlistName)
    private var scanning = false
    private var scanGeneration = 0
    private var status = "Scanning volumes…"
    private var backend = "kernel"
    private var timer: Timer?
    private var outputWindow: NSWindow?
    private var verifiedIdentities: [String: String] = [:]
    private var displayedReport = ""
    private var lastOutput: String?
    private var operationStatus: String?
    private var menuTracking = false
    private var menuNeedsRebuild = false
    private let progress = NSProgressIndicator()
    private var scanReport = "No scan has completed yet."

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = brandImage(size: 22, template: true)
        statusItem.button?.image?.accessibilityDescription = "mouNTFS"
        UserDefaults.standard.register(defaults: ["openFinderAfterMount": true, "showVolumeCount": false, "touchIDForHelper": true])
        progress.style = .spinning
        progress.controlSize = .small
        progress.isIndeterminate = true
        progress.isDisplayedWhenStopped = false
        progress.frame = NSRect(x: 3, y: 3, width: 16, height: 16)
        statusItem.button?.addSubview(progress)
        rebuildMenu()
        refresh()
        refreshHelperStatus()
        let poll = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(poll, forMode: .common)
        timer = poll
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(disksChanged(_:)), name: NSWorkspace.didMountNotification, object: nil)
        center.addObserver(self, selector: #selector(disksChanged(_:)), name: NSWorkspace.didUnmountNotification, object: nil)
    }

    private func item(_ title: String, action: Selector? = nil, object: Any? = nil) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.representedObject = object
        if action == nil { entry.isEnabled = false }
        return entry
    }

    private func rebuildMenu() {
        if menuTracking { menuNeedsRebuild = true; return }
        let menu = statusItem.menu ?? NSMenu()
        menu.removeAllItems()
        menu.delegate = self
        menu.autoenablesItems = false
        let header = item("mouNTFS")
        header.view = MenuHeaderView(status: status, version: appVersion)
        menu.addItem(header)
        menu.addItem(.separator())
        for volume in volumes {
            let entry = item(volume.name)
            let state = volume.mountPoint == nil ? "Unmounted" : (volume.readOnly ? "Read-only" : "Writable")
            let color: NSColor = volume.mountPoint == nil ? .secondaryLabelColor : (volume.readOnly ? .secondaryLabelColor : .systemGreen)
            let title = NSMutableAttributedString(string: volume.name, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor])
            title.append(NSAttributedString(string: "  ·  " + state, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: color]))
            entry.attributedTitle = title
            entry.image = menuSymbol("externaldrive", description: state)
            menu.addItem(entry)
            let mount = item(volume.readOnly ? "Enable Write Access…" : "Write Access Enabled", action: #selector(mountVolume(_:)), object: volume)
            mount.image = menuSymbol(volume.readOnly ? "lock.open" : "checkmark.circle.fill", description: mount.title)
            mount.isEnabled = !busy && volume.readOnly && volume.mediaIdentity != nil
            mount.indentationLevel = 1
            menu.addItem(mount)
            if let point = volume.mountPoint {
                let open = item("Open in Finder", action: #selector(openVolume(_:)), object: point)
                open.image = menuSymbol("folder", description: open.title)
                open.isEnabled = !busy
                open.indentationLevel = 1
                menu.addItem(open)
            }
            let eject = item("Safely Eject…", action: #selector(ejectVolume(_:)), object: volume)
            eject.image = menuSymbol("eject", description: eject.title)
            eject.isEnabled = !busy && volume.mediaIdentity != nil
            eject.indentationLevel = 1
            menu.addItem(eject)
            menu.addItem(.separator())
        }
        if volumes.isEmpty {
            menu.addItem(item("Connect an external NTFS drive"))
            menu.addItem(.separator())
        }
        let refreshItem = item("Refresh Volumes", action: #selector(refreshAction))
        refreshItem.image = menuSymbol("arrow.clockwise", description: refreshItem.title)
        refreshItem.isEnabled = !busy
        menu.addItem(refreshItem)
        let settings = NSMenu()
        settings.autoenablesItems = false
        let finder = item("Open Finder after enabling writing", action: #selector(toggleOpenFinder))
        finder.state = UserDefaults.standard.bool(forKey: "openFinderAfterMount") ? .on : .off
        settings.addItem(finder)
        let count = item("Show volume count in menu bar", action: #selector(toggleVolumeCount))
        count.state = UserDefaults.standard.bool(forKey: "showVolumeCount") ? .on : .off
        settings.addItem(count)
        settings.addItem(.separator())
        settings.addItem(item("Permission Helper · " + helperStatus))
        let enable = item(helperReady ? "Refresh Protected NTFS Driver…" : "Enable Permission Helper…", action: #selector(enableHelper))
        enable.isEnabled = !busy
        settings.addItem(enable)
        let repair = item("Repair Permission Helper Registration…", action: #selector(repairHelperRegistration))
        repair.isEnabled = !busy && !helperReady
        settings.addItem(repair)
        let disable = item("Disable Permission Helper…", action: #selector(disableHelper))
        disable.isEnabled = !busy && helperService.status != .notRegistered
        settings.addItem(disable)
        let biometric = item("Confirm helper mounts with Touch ID", action: #selector(toggleTouchID))
        biometric.state = UserDefaults.standard.bool(forKey: "touchIDForHelper") ? .on : .off
        biometric.isEnabled = !busy
        settings.addItem(biometric)
        settings.addItem(.separator())
        settings.addItem(item("NTFS Driver Permissions…", action: #selector(showPermissionHelp)))
        let preferences = item("Settings")
        preferences.isEnabled = true
        preferences.image = menuSymbol("gearshape", description: preferences.title)
        preferences.submenu = settings
        menu.addItem(preferences)
        let diagnostics = NSMenu()
        diagnostics.autoenablesItems = false
        let last = item("Show Last Operation…", action: #selector(showLastOperation))
        last.isEnabled = lastOutput != nil
        diagnostics.addItem(last)
        let diagnostic = item("Check Installation…", action: #selector(diagnose))
        diagnostic.isEnabled = !busy
        diagnostics.addItem(diagnostic)
        diagnostics.addItem(item("Show Disk Scan Report…", action: #selector(showScanReport)))
        let backendItem = item(backend == "kernel" ? "Use Experimental FSKit Backend" : "Use Kernel Backend",
                               action: #selector(toggleBackend))
        backendItem.isEnabled = !busy
        diagnostics.addItem(backendItem)
        let advanced = item("Diagnostics")
        advanced.isEnabled = true
        advanced.image = menuSymbol("stethoscope", description: advanced.title)
        advanced.submenu = diagnostics
        menu.addItem(advanced)
        let quit = item("Quit mouNTFS", action: #selector(quitApp))
        quit.isEnabled = !busy
        menu.addItem(.separator())
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private var menuBarTitle: String {
        UserDefaults.standard.bool(forKey: "showVolumeCount") && !volumes.isEmpty ? " \(volumes.count)" : ""
    }
    @objc private func toggleVolumeCount() {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "showVolumeCount"), forKey: "showVolumeCount")
        statusItem.button?.title = menuBarTitle
        rebuildMenu()
    }
    @objc private func refreshAction() { operationStatus = nil; refresh(); refreshHelperStatus() }
    @objc private func toggleTouchID() {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "touchIDForHelper"), forKey: "touchIDForHelper")
        rebuildMenu()
    }
    private func refreshHelperStatus() {
        guard !busy else { return }
        switch helperService.status {
        case .enabled:
            DispatchQueue.global(qos: .utility).async {
                let result = bundledHelperCommand(["--helper-status"])
                DispatchQueue.main.async {
                    guard !self.busy else { return }
                    self.helperReady = result.status == 0 && result.text.hasPrefix("ready\n")
                    self.helperStatus = self.helperReady ? "Ready" : "Needs setup / update"
                    self.rebuildMenu()
                }
            }
        case .requiresApproval: helperReady = false; helperStatus = "Needs system approval"; rebuildMenu()
        case .notFound: helperReady = false; helperStatus = "Missing bundled service"; rebuildMenu()
        default: helperReady = false; helperStatus = "Not enabled"; rebuildMenu()
        }
    }
    @objc private func enableHelper() {
        guard !busy else { return }
        NSApp.activate(ignoringOtherApps: true)
        guard Bundle.main.bundlePath.hasPrefix("/Applications/"), Bundle.main.bundlePath.hasSuffix(".app") else {
            showOutput(title: "Install before enabling helper", text: "Quit mouNTFS, move mouNTFS.app into /Applications, and reopen it there. The system service follows the installed application; do not enable it from a temporary download directory.")
            return
        }
        let alert = NSAlert()
        alert.messageText = helperReady ? "Refresh the protected NTFS driver?" : "Enable the permission helper?"
        alert.informativeText = "macOS may request setup approval and administrator authorization. The helper prepares a protected copy of the installed ntfs-3g driver and its libraries, then handles limited external NTFS mount operations without requesting a password for each command. You can disable it in Settings. Touch ID confirmations are available after setup on supported Macs."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            if helperService.status == .requiresApproval {
                showHelperApproval()
                return
            }
            if helperService.status != .enabled {
                do {
                    try helperService.register()
                } catch {
                    // register() can throw EPERM after adding an unapproved daemon.
                    // Check the post-registration state before treating this as failure.
                    let failure = error as NSError
                    if helperService.status == .requiresApproval ||
                        (failure.domain == "SMAppServiceErrorDomain" && failure.code == 1) {
                        showHelperApproval(error: error)
                        return
                    }
                    throw error
                }
            }
            if helperService.status == .requiresApproval {
                showHelperApproval()
                return
            }
            guard helperService.status == .enabled else { throw HelperError.invalid("The system has not enabled the helper.") }
            guard let driver = ["/opt/homebrew/bin/ntfs-3g", "/usr/local/bin/ntfs-3g"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }),
                  let client = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("mountfs-identity").path else {
                throw HelperError.invalid("Install ntfs-3g before setting up the helper.")
            }
            execute("Setting up permission helper…", executable: client, arguments: ["--helper-configure", driver], showSuccessOutput: true)
        } catch {
            showOutput(title: "Helper setup failed", text: helperSetupDetails(error))
        }
    }
    private func showHelperApproval(error: Error? = nil) {
        helperReady = false
        let pending = helperService.status == .requiresApproval
        helperStatus = pending ? "Needs system approval" : "Registration needs attention"
        rebuildMenu()
        SMAppService.openSystemSettingsLoginItems()
        var text = "Allow mouNTFS in System Settings → General → Login Items & Extensions (Allow in the Background). Return to Settings → Enable Permission Helper to finish the protected driver setup. Full Disk Access is a separate permission."
        if !pending {
            text += "\n\nIf mouNTFS is absent from that page, registration may have been rejected for another reason. This development package uses ad-hoc signing unless built with an Apple-issued signing identity; ad-hoc signatures can cause SMAppService registration and approval persistence problems. Copy the details below rather than repeatedly granting disk access."
        }
        if let error = error { text += "\n\n" + helperSetupDetails(error) }
        showOutput(title: pending ? "Approve the helper" : "Check helper approval", text: text)
    }
    private func helperSetupDetails(_ error: Error) -> String {
        let failure = error as NSError
        var lines = ["Stage: service registration / setup preflight",
                     "Error: \(failure.domain) / \(failure.code): \(failure.localizedDescription)",
                     "Service status: \(helperService.status.rawValue)",
                     "Application: \(Bundle.main.bundlePath)"]
        if let reason = failure.localizedFailureReason { lines.append("Reason: " + reason) }
        if let underlying = failure.userInfo[NSUnderlyingErrorKey] as? NSError {
            lines.append("Underlying: \(underlying.domain) / \(underlying.code): \(underlying.localizedDescription)")
        }
        if let specific = error as? HelperError { lines.append(specific.message) }
        for path in [Bundle.main.bundlePath, Bundle.main.bundlePath + "/Contents/MacOS/mountfs-helper"] {
            let signature = runCommand("/usr/bin/codesign", ["-d", "--verbose=4", path])
            lines.append("Signature (\(path)):\n" + signature.text)
        }
        return lines.joined(separator: "\n")
    }
    @objc private func repairHelperRegistration() {
        guard !busy, !helperReady else { return }
        NSApp.activate(ignoringOtherApps: true)
        guard Bundle.main.bundlePath.hasPrefix("/Applications/"), Bundle.main.bundlePath.hasSuffix(".app") else {
            showOutput(title: "Install before repairing helper", text: "Move mouNTFS.app into /Applications, reopen it there, and retry.")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Repair this app's helper registration?"
        alert.informativeText = "Unregister mouNTFS's helper, refresh this application's Launch Services record, and register its bundled helper again. macOS may request background-service approval. Protected driver copies are retained. After repair, select Enable Permission Helper to check the connection and finish setup."
        alert.addButton(withTitle: "Repair")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        busy = true; rebuildMenu()
        Task {
            do {
                // Wait for the specific service's removal before submitting it again.
                if helperService.status != .notRegistered { try await helperService.unregister() }
                await MainActor.run {
                    do {
                        let result = LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
                        guard result == noErr else {
                            throw HelperError.invalid("Launch Services registration failed: OSStatus \(result)")
                        }
                        try self.helperService.register()
                        self.busy = false
                        self.refreshHelperStatus()
                        if self.helperService.status == .requiresApproval { self.showHelperApproval() }
                        else { self.showOutput(title: "Helper registration refreshed", text: "Registration was resubmitted. Select Settings → Enable Permission Helper to verify that the daemon can start and finish driver setup. Registration alone does not establish a working helper.") }
                    } catch {
                        self.busy = false; self.helperReady = false; self.refreshHelperStatus()
                        let failure = error as NSError
                        if self.helperService.status == .requiresApproval ||
                            (failure.domain == "SMAppServiceErrorDomain" && failure.code == 1) { self.showHelperApproval(error: error) }
                        else { self.showOutput(title: "Helper registration repair failed", text: self.helperSetupDetails(error)) }
                    }
                }
            } catch {
                await MainActor.run {
                    self.busy = false; self.refreshHelperStatus()
                    self.showOutput(title: "Helper unregister failed; repair stopped", text: self.helperSetupDetails(error))
                }
            }
        }
    }
    @objc private func disableHelper() {
        guard !busy else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Disable the permission helper?"
        alert.informativeText = "Future mounts will use the original administrator authorization flow. Already committed mounts stay connected. Protected driver copies are retained so active mounts can keep using them."
        alert.addButton(withTitle: "Disable")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        busy = true; rebuildMenu()
        Task {
            do {
                try await helperService.unregister()
                await MainActor.run { self.busy = false; self.helperReady = false; self.refreshHelperStatus() }
            } catch {
                await MainActor.run { self.busy = false; self.refreshHelperStatus(); self.showOutput(title: "Could not disable helper", text: error.localizedDescription) }
            }
        }
    }
    @objc private func showPermissionHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Allow the NTFS driver to access your drive"
        let protectedDriverNote = helperReady ? "The helper uses a protected ntfs-3g copy. Its exact path appears in the helper setup report or operation details. Grant access to that copy if macOS denies device access. " : ""
        alert.informativeText = protectedDriverNote + "In System Settings → Privacy & Security → Full Disk Access, add the actual ntfs-3g executable. Check Installation shows its installed path. Granting access only to mouNTFS may not cover the driver. Administrator authorization and Full Disk Access are separate permissions."
        alert.addButton(withTitle: "Open Full Disk Access")
        alert.addButton(withTitle: "Check Installation")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: openFullDiskAccess()
        case .alertSecondButtonReturn: if !busy { diagnose() }
        default: break
        }
    }
    @objc private func openFullDiskAccess() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
    @objc private func disksChanged(_ notification: Notification) {
        DispatchQueue.main.async { self.operationStatus = nil; self.refresh() }
    }
    func menuWillOpen(_ menu: NSMenu) { menuTracking = true; refresh() }
    func menuDidClose(_ menu: NSMenu) {
        menuTracking = false
        if menuNeedsRebuild { menuNeedsRebuild = false; rebuildMenu() }
    }
    @objc private func toggleOpenFinder() {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "openFinderAfterMount"), forKey: "openFinderAfterMount")
        rebuildMenu()
    }
    @objc private func showLastOperation() {
        if let lastOutput { showOutput(title: "Last Operation", text: lastOutput) }
    }
    @objc private func showScanReport() { showOutput(title: "Disk Scan Report", text: scanReport) }

    private func refresh() {
        guard !busy, !scanning else { return }
        scanning = true
        let identities = verifiedIdentities
        let generation = scanGeneration
        DispatchQueue.global(qos: .utility).async {
            let result = scanVolumes(verifiedIdentities: identities)
            DispatchQueue.main.async {
                self.scanning = false
                guard !self.busy else { return }
                guard generation == self.scanGeneration else { self.refresh(); return }
                let oldVolumes = self.volumes
                let oldStatus = self.status
                if let result = result {
                    self.volumes = result.volumes
                    self.scanReport = result.report
                    self.status = self.operationStatus ?? "\(result.volumes.count) external NTFS volume(s)"
                } else {
                    self.volumes = []
                    self.status = "Cannot read disk information — retry Refresh"
                    self.scanReport = "diskutil list failed or returned an unreadable plist. Check Disk Utility and retry Refresh."
                }
                self.statusItem.button?.title = self.menuBarTitle
                self.statusItem.button?.toolTip = "mouNTFS — \(self.status)"
                if oldVolumes != self.volumes || oldStatus != self.status { self.rebuildMenu() }
            }
        }
    }

    private func scriptPath() -> String? {
        // Distributed apps only execute their own bundled core.
        if let resource = Bundle.main.url(forResource: "mountfs", withExtension: "sh") {
            return resource.path
        }
        // Development through `swift run` from the checkout.
        if !Bundle.main.bundlePath.hasSuffix(".app") {
            let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("mountfs.sh").path
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }

    private func execute(_ title: String, executable: String, arguments: [String], showSuccessOutput: Bool = false, mountDevice: String? = nil, selectedVolume: Volume? = nil) {
        guard !busy else { return }
        busy = true
        scanGeneration += 1
        status = title
        statusItem.button?.image = nil
        statusItem.button?.title = "   "
        statusItem.button?.toolTip = title
        progress.startAnimation(nil)
        let identities = verifiedIdentities
        let generationForStatus = scanGeneration
        var environment = ProcessInfo.processInfo.environment
        environment["MOUNTFS_PRIVILEGED_HELPER"] = mountDevice != nil && helperReady ? "1" : "0"
        let operationEnvironment = environment
        rebuildMenu()
        DispatchQueue.global(qos: .userInitiated).async {
            let identity = selectedVolume?.mediaIdentity ?? mountDevice.flatMap { currentIdentity($0) }
            if let device = mountDevice, let info = diskDictionary(["info", "-plist", device]),
               let point = DiskMetadata(info).mountPoint, let directory = opendir(point) {
                closedir(directory)
            }
            let result: CommandResult
            if let selected = selectedVolume, selected.mediaIdentity == nil || currentIdentity(selected.device) != selected.mediaIdentity {
                result = CommandResult(status: 1, output: Data("Error: The selected drive disconnected or was replaced. Refresh the menu and select the drive again; no operation was started.\n".utf8))
            } else {
                result = runCommand(executable, arguments, environment: operationEnvironment)
            }
            var details = result.text
            if result.status != 0 && arguments.first == "--helper-configure" {
                details += "\n\n--- Helper launch state (read-only) ---\n"
                details += runCommand("/bin/launchctl", ["print", "system/" + helperServiceName]).text
                details += "\n\n--- Installed application signature ---\n"
                details += runCommand("/usr/bin/codesign", ["--verify", "--deep", "--strict", "--verbose=2", Bundle.main.bundlePath]).text
                details += "\n\n--- Helper signing identity ---\n"
                details += runCommand("/usr/bin/codesign", ["-d", "--verbose=4", Bundle.main.bundlePath + "/Contents/MacOS/mountfs-helper"]).text
            }
            if result.status != 0 && result.status != 2 && arguments.contains("--device") {
                let scan = scanVolumes(verifiedIdentities: identities)?.report ?? "Disk scan unavailable."
                let diagnosis = runCommand(executable, [arguments[0], "--diagnose"]).text
                details += "\n\n--- Read-only disk scan ---\n" + scan
                details += "\n\n--- Installation diagnosis ---\n" + diagnosis
            }
            let operationDetails = details
            let verifiedDevice = result.status == 0 ? mountDevice : nil
            let finalIdentity = verifiedDevice.flatMap { currentIdentity($0) }
            let finalState = verifiedDevice.flatMap { currentMountState($0) }
            let verifiedPoint = identity != nil && identity == finalIdentity && finalState?["WritableVolume"] as? Bool == true
                ? finalState?["MountPoint"] as? String : nil
            DispatchQueue.main.async {
                self.busy = false
                self.progress.stopAnimation(nil)
                self.statusItem.button?.image = brandImage(size: 22, template: true)
                self.statusItem.button?.title = self.menuBarTitle
                self.lastOutput = operationDetails
                if let device = verifiedDevice, let identity, verifiedPoint != nil {
                    self.verifiedIdentities[device] = identity
                }
                self.status = result.status == 0 ? (mountDevice == nil ? "Completed" : "Write access enabled") : (result.status == 2 ? "Cancelled" : "Operation failed")
                self.operationStatus = self.status
                self.statusItem.button?.toolTip = "mouNTFS — \(self.status)"
                self.rebuildMenu()
                if result.status != 0 && result.status != 2 {
                    NSApp.activate(ignoringOtherApps: true)
                    let alert = NSAlert()
                    alert.messageText = "The operation could not be completed"
                    alert.informativeText = result.text.components(separatedBy: .newlines)
                        .first(where: { $0.hasPrefix("Error:") })
                        ?? "macOS or the driver could not complete the operation. Open Show Details for the operation log and read-only diagnostics."
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.addButton(withTitle: "Show Details")
                    let accessDenied = result.text.contains("Operation not permitted") || result.text.contains("Permission denied")
                    if accessDenied { alert.addButton(withTitle: "Open Full Disk Access") }
                    let choice = alert.runModal()
                    if choice == .alertThirdButtonReturn && accessDenied { self.openFullDiskAccess() }
                    if choice == .alertSecondButtonReturn {
                        self.showOutput(title: self.status, text: operationDetails)
                    }
                } else if result.status == 0 && showSuccessOutput {
                    self.showOutput(title: self.status, text: operationDetails)
                }
                if let point = verifiedPoint, !point.isEmpty, UserDefaults.standard.bool(forKey: "openFinderAfterMount") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: point))
                }
                self.refresh()
                self.refreshHelperStatus()
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                    guard !self.busy, self.scanGeneration == generationForStatus else { return }
                    self.operationStatus = nil
                    self.refresh()
                }
            }
        }
    }

    @objc private func mountVolume(_ sender: NSMenuItem) {
        guard !busy, let selected = sender.representedObject as? Volume, let identity = selected.mediaIdentity else { return }
        let device = selected.device
        guard let script = scriptPath() else { showOutput(title: "Installation incomplete", text: "Bundled mountfs.sh was not found. Rebuild the app with scripts/build-app.sh."); return }
        let performMount = { [weak self] in
            self?.execute("Enabling write access…", executable: "/bin/bash", arguments: [script, "--device", device, "--backend", self?.backend ?? "kernel", "--app-action", "--expected-identity", identity], mountDevice: device, selectedVolume: selected)
        }
        if helperReady && UserDefaults.standard.bool(forKey: "touchIDForHelper") {
            let context = LAContext()
            var error: NSError?
            let biometricAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
            // Lockout / a closed lid must use the native password fallback,
            // rather than silently skipping confirmation on a Touch ID Mac.
            if biometricAvailable || context.biometryType == .touchID {
                busy = true; status = "Waiting for Touch ID…"; rebuildMenu()
                NSApp.activate(ignoringOtherApps: true)
                context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "enable write access to " + selected.name) { success, _ in
                    DispatchQueue.main.async {
                        self.busy = false
                        if success { performMount() }
                        else { self.operationStatus = "Authorization cancelled"; self.refresh(); self.rebuildMenu() }
                    }
                }
                return
            }
        }
        performMount()
    }

    @objc private func openVolume(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func ejectVolume(_ sender: NSMenuItem) {
        guard !busy, let selected = sender.representedObject as? Volume, selected.mediaIdentity != nil else { return }
        let device = selected.device
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Safely eject this drive?"
        alert.informativeText = "This ejects the physical disk containing \(device), including its other volumes."
        alert.addButton(withTitle: "Eject")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        execute("Ejecting…", executable: "/usr/sbin/diskutil", arguments: ["eject", device], selectedVolume: selected)
    }

    @objc private func diagnose() {
        guard let script = scriptPath() else { return }
        execute("Checking installation…", executable: "/bin/bash", arguments: [script, "--diagnose", "--backend", backend], showSuccessOutput: true)
    }

    @objc private func toggleBackend() {
        if backend == "kernel" {
            let alert = NSAlert()
            alert.messageText = "Try the experimental FSKit backend?"
            alert.informativeText = "Requires macOS 15.4+ and compatible drivers. mouNTFS has not yet completed real-disk validation of this backend. The selection lasts for this app session."
            alert.addButton(withTitle: "Use FSKit")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            backend = "fskit"
        } else { backend = "kernel" }
        rebuildMenu()
    }

    private func showOutput(title: String, text: String) {
        let window = outputWindow ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 380), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "mouNTFS — \(title)"
        let content = NSView(frame: window.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        let copy = NSButton(title: "Copy Report", target: self, action: #selector(copyReport))
        copy.bezelStyle = .rounded
        copy.frame = NSRect(x: 14, y: 10, width: 116, height: 28)
        content.addSubview(copy)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 48, width: content.bounds.width, height: content.bounds.height - 48))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        let view = NSTextView(frame: scroll.bounds)
        view.isEditable = false
        view.isSelectable = true
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.string = text
        view.textContainerInset = NSSize(width: 12, height: 12)
        view.autoresizingMask = [.width]
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        scroll.documentView = view
        content.addSubview(scroll)
        displayedReport = text
        window.contentView = content
        outputWindow = window
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func copyReport() {
        let report = displayedReport
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    @objc private func quitApp() { if !busy { NSApp.terminate(nil) } }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
