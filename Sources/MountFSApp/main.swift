import AppKit
import Darwin
import MountFSCore

let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.9"

func helperResult(_ option: String, device: String) -> CommandResult? {
    let candidates: [String?] = [Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("mountfs-identity").path,
                      URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build/release/MountFSIdentity").path]
    guard let path = candidates.compactMap({ $0 }).first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
    return runCommand(path, [option, device], mergeErrors: false)
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
func runCommand(_ executable: String, _ arguments: [String], mergeErrors: Bool = true) -> CommandResult {
    let process = Process()
    let pipe = Pipe()
    let errorPipe = Pipe()
    let errors = ErrorCapture()
    let group = DispatchGroup()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
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
        return Volume(device: device, name: disk.name, mountPoint: disk.mountPoint, readOnly: disk.readOnly)
    }
    report.append("Included \(volumes.count) external NTFS partition(s).")
    return ScanResult(volumes: volumes, report: report.joined(separator: "\n"))
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var volumes: [Volume] = []
    private var busy = false
    private var scanning = false
    private var scanGeneration = 0
    private var status = "Scanning volumes…"
    private var backend = "kernel"
    private var timer: Timer?
    private var outputWindow: NSWindow?
    private var verifiedIdentities: [String: String] = [:]
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
        UserDefaults.standard.register(defaults: ["openFinderAfterMount": true])
        progress.style = .spinning
        progress.controlSize = .small
        progress.isIndeterminate = true
        progress.isDisplayedWhenStopped = false
        progress.frame = NSRect(x: 3, y: 3, width: 16, height: 16)
        statusItem.button?.addSubview(progress)
        rebuildMenu()
        refresh()
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
        menu.addItem(item("mouNTFS \(appVersion)"))
        menu.addItem(item(status))
        menu.addItem(.separator())
        for volume in volumes {
            let entry = item("\(volume.name) · \(volume.readOnly ? "Read-only" : "Writable")")
            entry.isEnabled = true
            let actions = NSMenu()
            actions.autoenablesItems = false
            let mount = item("Enable Write Access…", action: #selector(mountVolume(_:)), object: volume.device)
            mount.isEnabled = !busy && volume.readOnly
            actions.addItem(mount)
            if let point = volume.mountPoint {
                let open = item("Open in Finder", action: #selector(openVolume(_:)), object: point)
                open.isEnabled = !busy
                actions.addItem(open)
            }
            let eject = item("Safely Eject…", action: #selector(ejectVolume(_:)), object: volume.device)
            eject.isEnabled = !busy
            actions.addItem(eject)
            entry.submenu = actions
            menu.addItem(entry)
        }
        if volumes.isEmpty { menu.addItem(item("No external NTFS volumes")) }
        menu.addItem(.separator())
        let refreshItem = item("Refresh", action: #selector(refreshAction))
        refreshItem.isEnabled = !busy
        menu.addItem(refreshItem)
        let finder = item("Open Finder after enabling writing", action: #selector(toggleOpenFinder))
        finder.state = UserDefaults.standard.bool(forKey: "openFinderAfterMount") ? .on : .off
        menu.addItem(finder)
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
        advanced.submenu = diagnostics
        menu.addItem(advanced)
        let quit = item("Quit mouNTFS", action: #selector(quitApp))
        quit.isEnabled = !busy
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func refreshAction() { refresh() }
    @objc private func disksChanged(_ notification: Notification) {
        DispatchQueue.main.async { self.refresh() }
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
                self.statusItem.button?.title = self.volumes.isEmpty ? "" : " \(self.volumes.count)"
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

    private func execute(_ title: String, executable: String, arguments: [String], showSuccessOutput: Bool = false, mountDevice: String? = nil) {
        guard !busy else { return }
        busy = true
        scanGeneration += 1
        status = title
        statusItem.button?.image = nil
        statusItem.button?.title = "   "
        statusItem.button?.toolTip = title
        progress.startAnimation(nil)
        let identities = verifiedIdentities
        rebuildMenu()
        DispatchQueue.global(qos: .userInitiated).async {
            let identity = mountDevice.flatMap { currentIdentity($0) }
            if let device = mountDevice, let info = diskDictionary(["info", "-plist", device]),
               let point = DiskMetadata(info).mountPoint, let directory = opendir(point) {
                closedir(directory)
            }
            let result = runCommand(executable, arguments)
            var details = result.text
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
                self.statusItem.button?.title = self.volumes.isEmpty ? "" : " \(self.volumes.count)"
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
                    if alert.runModal() == .alertSecondButtonReturn {
                        self.showOutput(title: self.status, text: operationDetails)
                    }
                } else if result.status == 0 && showSuccessOutput {
                    self.showOutput(title: self.status, text: operationDetails)
                }
                if let point = verifiedPoint, !point.isEmpty, UserDefaults.standard.bool(forKey: "openFinderAfterMount") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: point))
                }
                self.refresh()
            }
        }
    }

    @objc private func mountVolume(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? String else { return }
        guard let script = scriptPath() else { showOutput(title: "Installation incomplete", text: "Bundled mountfs.sh was not found. Rebuild the app with scripts/build-app.sh."); return }
        execute("Enabling write access…", executable: "/bin/bash", arguments: [script, "--device", device, "--backend", backend, "--app-action"], mountDevice: device)
    }

    @objc private func openVolume(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func ejectVolume(_ sender: NSMenuItem) {
        guard !busy, let device = sender.representedObject as? String else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Safely eject this drive?"
        alert.informativeText = "This ejects the physical disk containing \(device), including its other volumes."
        alert.addButton(withTitle: "Eject")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        execute("Ejecting…", executable: "/usr/sbin/diskutil", arguments: ["eject", device])
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
        let scroll = NSScrollView(frame: window.contentView!.bounds)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        let view = NSTextView(frame: scroll.bounds)
        view.isEditable = false
        view.isSelectable = true
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.string = text
        view.autoresizingMask = [.width]
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        scroll.documentView = view
        window.contentView = scroll
        outputWindow = window
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func quitApp() { if !busy { NSApp.terminate(nil) } }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
