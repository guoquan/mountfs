import Foundation
import os.log
import Darwin
import MountFSPrivileged

private let work = DispatchQueue(label: "net.guoquan.mountfs.helper.transactions")
private var lockedDevices = Set<String>() // Accessed only on work.

private func externalNTFS(_ device: String) -> Bool {
    let result = runTool("/usr/sbin/diskutil", ["info", "-plist", device])
    guard result.status == 0, let data = result.output.data(using: .utf8),
          let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return false }
    return info["DeviceIdentifier"] as? String == device && info["Internal"] as? Bool == false &&
        info["WholeDisk"] as? Bool == false && info["FilesystemType"] as? String == "ntfs"
}

private final class Transaction {
    let device: String
    let identity: String
    let originalPoint: String
    let driver: String
    let uid: uid_t
    let gid: gid_t
    let deadline = ProcessInfo.processInfo.systemUptime + 300
    let lockToken = UUID().uuidString
    var point: String?
    var driverUsed = false
    var touched = false
    var committed = false
    var commitAcknowledged = false
    var mayReleaseLock: Bool { !terminationUnconfirmed && (!committed || commitAcknowledged) }
    var terminationUnconfirmed = false
    init(device: String, identity: String, original: String, configuration: DriverConfiguration, gid: gid_t) {
        self.device = device; self.identity = identity; originalPoint = original
        driver = configuration.executable; uid = configuration.uid; self.gid = gid
    }
    func current() -> [String: Any]? {
        guard !terminationUnconfirmed, mediaIdentity(device) == identity else { return nil }
        return mountState(device)
    }
    private func tool(_ path: String, _ args: [String], timeout: TimeInterval = 30) -> HelperReply {
        let result = runTool(path, args, timeout: timeout)
        if result.status == 125 { terminationUnconfirmed = true }
        return result
    }
    func perform(_ operation: String) -> HelperReply {
        if operation == "acknowledge" {
            guard committed, !terminationUnconfirmed, ProcessInfo.processInfo.systemUptime < deadline else {
                return HelperReply(1, "No confirmed commit to acknowledge.")
            }
            commitAcknowledged = true
            return HelperReply(0, "Caller acknowledged the committed mount.")
        }
        guard ["prepare", "unmount", "mount-kernel", "mount-fskit", "recover", "cleanup", "commit"].contains(operation),
              ProcessInfo.processInfo.systemUptime < deadline, let state = current() else {
            return HelperReply(1, "Helper refused an invalid, expired or replaced-device transaction.")
        }
        let mounted = state["MountPoint"] as? String ?? ""
        switch operation {
        case "prepare":
            guard point == nil else { return HelperReply(1, "Mount directory already prepared.") }
            var template = Array(("/Volumes/mountfs." + device + ".XXXXXXXX").utf8CString)
            guard let created = mkdtemp(&template) else { return HelperReply(1, "Cannot prepare controlled mount directory.") }
            point = String(cString: created)
            return HelperReply(0, point!)
        case "unmount":
            guard !committed, !mounted.isEmpty, mounted == originalPoint || mounted == point else {
                return HelperReply(1, "Unrelated or absent mount was left unchanged.")
            }
            touched = true
            return tool("/usr/sbin/diskutil", ["unmount", device])
        case "mount-kernel", "mount-fskit":
            guard !committed, !driverUsed, mounted.isEmpty, let point,
                  rootDirectory(point), secureAncestors(point), rootFile(driver), secureAncestors(driver) else {
                return HelperReply(1, "Driver replay, unsafe directory or duplicate mount refused.")
            }
            touched = true; driverUsed = true
            let backend = operation == "mount-kernel" ? "local" : "backend=fskit"
            guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else {
                return HelperReply(1, "This macOS does not provide the protected driver execution facility. Disable the helper to use the original authorization flow.")
            }
            // ntfs-3g can dlopen external reparse plugins as well as its linked
            // libraries. Prevent a persistent root driver from reading code or
            // plugins out of mutable Homebrew/user directories after setup.
            return tool("/usr/bin/sandbox-exec", ["-p", driverSandboxProfile, driver, "/dev/" + device, point, "-o",
                "rw,norecover,allow_other,default_permissions,uid=\(uid),gid=\(gid),umask=077," + backend],
                timeout: min(60, max(1, deadline - ProcessInfo.processInfo.systemUptime)))
        case "recover":
            guard !committed, mounted.isEmpty else { return HelperReply(1, "Recovery requires an unmounted selected device.") }
            return tool("/usr/sbin/diskutil", ["mount", "readOnly", device])
        case "cleanup":
            guard let point, mounted != point else { return HelperReply(1, "Active mount directory retained.") }
            return tool("/bin/rmdir", [point])
        case "commit":
            guard !committed, driverUsed, let point, mounted == point,
                  state["WritableVolume"] as? Bool == true else { return HelperReply(1, "Cannot commit an unverified mount.") }
            committed = true
            return HelperReply(0, "Helper transaction committed.")
        default: return HelperReply(1, "Unknown helper operation.")
        }
    }
    // Connection loss/expiry never matches a new disk or unmounts another path.
    // Committed mounts survive disconnect; their lock requires caller acknowledgement.
    func abort() {
        guard !committed, let state = current() else { return }
        var mounted = state["MountPoint"] as? String ?? ""
        if touched, let point, mounted == point {
            guard tool("/usr/sbin/diskutil", ["unmount", device]).status == 0,
                  let fresh = current() else { return }
            mounted = fresh["MountPoint"] as? String ?? ""
        }
        if touched, mounted.isEmpty, current() != nil { _ = tool("/usr/sbin/diskutil", ["mount", "readOnly", device]) }
        if let point, let fresh = current(), fresh["MountPoint"] as? String != point {
            _ = tool("/bin/rmdir", [point])
        }
    }
}

private final class ClientService: NSObject, MountHelperProtocol {
    let uid: uid_t
    let gid: gid_t
    private var transaction: Transaction?
    init(uid: uid_t, gid: gid_t) { self.uid = uid; self.gid = gid }
    func status(withReply reply: @escaping (String) -> Void) {
        work.async {
            guard let configuration = DriverConfiguration.load(), configuration.uid == self.uid else { reply("unconfigured"); return }
            reply("ready\n" + configuration.executable)
        }
    }
    func configure(_ driver: String, authorization: Data, withReply reply: @escaping (Int32, String) -> Void) {
        work.async {
            guard lockedDevices.isEmpty, verifyAdministratorAuthorization(authorization) else {
                reply(1, "Driver setup requires administrator authorization and no active transaction."); return
            }
            do { reply(0, try configureDriver(driver, uid: self.uid)) }
            catch { reply(1, (error as? HelperError)?.message ?? error.localizedDescription) }
        }
    }
    func begin(_ device: String, identity: String, withReply reply: @escaping (Int32, String) -> Void) {
        work.async {
            guard self.transaction == nil, !lockedDevices.contains(device),
                  let configuration = DriverConfiguration.load(), configuration.uid == self.uid,
                  externalNTFS(device), mediaIdentity(device) == identity, let state = mountState(device) else {
                reply(1, "Cannot begin an authorized external NTFS helper transaction."); return
            }
            let transaction = Transaction(device: device, identity: identity, original: state["MountPoint"] as? String ?? "", configuration: configuration, gid: self.gid)
            do { try SystemDeviceLock.perform("acquire", device: device, token: transaction.lockToken) }
            catch { reply(1, "System-wide device lock failed: \(error)"); return }
            self.transaction = transaction
            lockedDevices.insert(device)
            work.asyncAfter(deadline: .now() + 300) { [weak self, weak transaction] in
                guard let self, let transaction, self.transaction === transaction else { return }
                self.close()
            }
            reply(0, "Helper session ready.\nProtected ntfs-3g: " + configuration.executable)
        }
    }
    func perform(_ operation: String, withReply reply: @escaping (Int32, String) -> Void) {
        work.async {
            guard let transaction = self.transaction else { reply(1, "No active helper transaction."); return }
            let result = transaction.perform(operation)
            reply(result.status, result.output)
        }
    }
    private func close() {
        guard let transaction else { return }
        transaction.abort()
        if transaction.mayReleaseLock {
            do {
                try SystemDeviceLock.perform("release", device: transaction.device, token: transaction.lockToken)
                lockedDevices.remove(transaction.device)
            } catch { helperLog.error("System-wide device lock retained after release failure") }
        }
        self.transaction = nil
    }
    func disconnected() { work.async { self.close() } }
}

private let helperLog = Logger(subsystem: helperServiceName, category: "service")

private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier > 0 else {
            helperLog.error("Rejected a root client connection")
            return false
        }
        helperLog.info("Accepted authenticated client connection")
        connection.setCodeSigningRequirement(allowedHelperClient)
        let service = ClientService(uid: connection.effectiveUserIdentifier, gid: connection.effectiveGroupIdentifier)
        connection.exportedInterface = NSXPCInterface(with: MountHelperProtocol.self)
        connection.exportedObject = service
        connection.invalidationHandler = { service.disconnected() }
        connection.interruptionHandler = { service.disconnected() }
        connection.resume()
        return true
    }
}

if CommandLine.arguments.contains("--self-test") {
    // No service registration, privileges, filesystem changes or disk mutation.
    guard !rootDirectory("/tmp"), !rootFile("/etc"), !verifyAdministratorAuthorization(Data()) else { exit(1) }
    let configuration = DriverConfiguration(uid: 501, source: "/opt/homebrew/bin/ntfs-3g", executable: "/tmp/untrusted-driver")
    let transaction = Transaction(device: "disk99999s1", identity: "not-live", original: "/Volumes/other", configuration: configuration, gid: 20)
    for operation in ["force", "arbitrary-command", "mount-kernel", "unmount", "recover", "commit"] {
        guard transaction.perform(operation).status != 0 else { exit(1) }
    }
    guard transaction.mayReleaseLock else { exit(1) }
    transaction.committed = true
    guard !transaction.mayReleaseLock else { exit(1) }
    guard transaction.perform("acknowledge").status == 0, transaction.mayReleaseLock else { exit(1) }
    transaction.terminationUnconfirmed = true
    guard !transaction.mayReleaseLock else { exit(1) }
    print("PASS committed helper lock survives missing acknowledgement and disconnect; confirmed caller completion permits release")
    let cache = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/mountfs-helper-test-" + UUID().uuidString)
    guard cache.path.hasPrefix("/Users/") else { exit(1) }
    do {
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: cache) }
        let source = cache.appendingPathComponent("source")
        try Data("safe binary bytes".utf8).write(to: source)
        let canonical = source.resolvingSymlinksInPath().path
        guard try readDriverSource(canonical) == Data("safe binary bytes".utf8) else { exit(1) }
        let link = cache.appendingPathComponent("source-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        do { _ = try readDriverSource(link.path); exit(1) } catch {}
        let ancestor = cache.appendingPathComponent("ancestor-link")
        try FileManager.default.createSymbolicLink(at: ancestor, withDestinationURL: cache)
        do { _ = try readDriverSource(ancestor.path + "/source"); exit(1) } catch {}
        do { _ = try readDriverSource(canonical, limit: 4); exit(1) } catch {}
        let timed = runTool("/bin/sh", ["-c", "trap '' TERM; sleep 30 & echo $!; wait"], timeout: 0.2)
        guard [124, 125].contains(timed.status), let child = Int32(timed.output.components(separatedBy: .newlines)[0]),
              !authorizationProcessIsLive(child) else { exit(1) }
        print("PASS descriptor driver reads reject leaf/ancestor links and oversize files; timed-out child is stopped")
        let plugin = cache.appendingPathComponent("untrusted-plugin")
        try Data("untrusted".utf8).write(to: plugin)
        guard runTool("/bin/cat", [plugin.path]).status == 0,
              runTool("/usr/bin/sandbox-exec", ["-p", driverSandboxProfile, "/usr/bin/true"]).status == 0,
              runTool("/usr/bin/sandbox-exec", ["-p", driverSandboxProfile, "/bin/cat", plugin.path]).status != 0 else { exit(1) }
    } catch { exit(1) }
    print("PASS driver sandbox allows system execution and rejects a real user-writable plugin read")
    print("PASS helper rejects writable storage, fake authorization, unknown operations and missing media before mutation")
    exit(0)
}
guard geteuid() == 0, allowedHelperClient.hasPrefix("cdhash ") else {
    helperLog.error("Helper startup rejected: requires root and a built client identity")
    exit(1)
}
let listener = NSXPCListener(machServiceName: helperServiceName)
private let delegate = ListenerDelegate()
listener.delegate = delegate
listener.setConnectionCodeSigningRequirement(allowedHelperClient)
listener.resume()
helperLog.info("Helper listener started")
// A bare Foundation run loop has no guaranteed input source. It can return
// immediately even while an XPC listener is active on its own dispatch queue.
// Keep the launchd daemon alive independently of run-loop sources.
dispatchMain()
