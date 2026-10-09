import AppKit

struct Volume {
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

// All commands use Process arguments; volume names are never evaluated as code.
func runCommand(_ executable: String, _ arguments: [String]) -> CommandResult {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus, output: output)
    } catch {
        return CommandResult(status: 1, output: Data(error.localizedDescription.utf8))
    }
}

func diskDictionary(_ arguments: [String]) -> [String: Any]? {
    let result = runCommand("/usr/sbin/diskutil", arguments)
    guard result.status == 0,
          let object = try? PropertyListSerialization.propertyList(from: result.output, format: nil)
    else { return nil }
    return object as? [String: Any]
}

func scanVolumes() -> [Volume]? {
    guard let list = diskDictionary(["list", "-plist"]), let disks = list["AllDisks"] as? [String]
    else { return nil }
    return disks.compactMap { device in
        guard let info = diskDictionary(["info", "-plist", device]),
              info["FilesystemType"] as? String == "ntfs",
              info["Internal"] as? Bool == false,
              info["Whole"] as? Bool == false else { return nil }
        return Volume(device: device, name: info["VolumeName"] as? String ?? device,
                      mountPoint: info["MountPoint"] as? String,
                      readOnly: info["ReadOnlyVolume"] as? Bool ?? true)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var volumes: [Volume] = []
    private var busy = false
    private var scanning = false
    private var status = "Scanning volumes…"
    private var backend = "kernel"
    private var timer: Timer?
    private var outputWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "externaldrive", accessibilityDescription: "mouNTFS")
        rebuildMenu()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    private func item(_ title: String, action: Selector? = nil, object: Any? = nil) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.representedObject = object
        if action == nil { entry.isEnabled = false }
        return entry
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("mouNTFS 0.2.0"))
        menu.addItem(item(status))
        menu.addItem(.separator())
        for volume in volumes {
            let entry = item("\(volume.name) · \(volume.readOnly ? "Read-only" : "Writable")")
            entry.isEnabled = true
            let actions = NSMenu()
            actions.autoenablesItems = false
            actions.addItem(item(volume.device))
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
        let diagnostic = item("Check Installation…", action: #selector(diagnose))
        diagnostic.isEnabled = !busy
        menu.addItem(diagnostic)
        let backendItem = item(backend == "kernel" ? "Use Experimental FSKit Backend" : "Use Kernel Backend",
                               action: #selector(toggleBackend))
        backendItem.isEnabled = !busy
        menu.addItem(backendItem)
        let quit = item("Quit mouNTFS", action: #selector(quitApp))
        quit.isEnabled = !busy
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func refreshAction() { refresh() }

    private func refresh() {
        guard !busy, !scanning else { return }
        scanning = true
        DispatchQueue.global(qos: .utility).async {
            let result = scanVolumes()
            DispatchQueue.main.async {
                self.scanning = false
                guard !self.busy else { return }
                if let result = result {
                    self.volumes = result
                    self.status = "\(result.count) external NTFS volume(s)"
                } else {
                    self.volumes = []
                    self.status = "Cannot read disk information — retry Refresh"
                }
                self.rebuildMenu()
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

    private func execute(_ title: String, executable: String, arguments: [String]) {
        guard !busy else { return }
        busy = true
        status = title
        rebuildMenu()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = runCommand(executable, arguments)
            DispatchQueue.main.async {
                self.busy = false
                self.status = result.status == 0 ? "Completed" : (result.status == 2 ? "Cancelled" : "Operation failed")
                self.rebuildMenu()
                if result.status != 2 { self.showOutput(title: self.status, text: result.text) }
                self.refresh()
            }
        }
    }

    @objc private func mountVolume(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? String else { return }
        guard let script = scriptPath() else { showOutput(title: "Installation incomplete", text: "Bundled mountfs.sh was not found. Rebuild the app with scripts/build-app.sh."); return }
        execute("Enabling write access…", executable: "/bin/bash", arguments: [script, "--device", device, "--backend", backend])
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
        execute("Checking installation…", executable: "/bin/bash", arguments: [script, "--diagnose", "--backend", backend])
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
