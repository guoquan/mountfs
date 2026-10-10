import Foundation
import Darwin
import Carbon
import MountFSPrivileged

// This host stays UNPRIVILEGED. One NSAppleScript instance owns the OS-managed
// authorization cache. Requests are bounded to this one partition/transaction.
private final class AuthorizationHost {
    private let script: NSAppleScript?
    private let privilegedClient: MountHelperClient?
    private let device: String?
    private let driver: String?
    init(administrator: Bool = true, privileged: Bool = false, device: String? = nil, driver: String? = nil) throws {
        self.device = device; self.driver = driver
        if privileged {
            guard let device, let identity = mediaIdentity(device) else { throw SessionError.invalid }
            let client = try MountHelperClient()
            let result = client.begin(device: device, identity: identity)
            guard result.status == 0 else {
                FileHandle.standardError.write(Data((result.output + "\n").utf8)); throw SessionError.invalid
            }
            FileHandle.standardError.write(Data((result.output + "\n").utf8))
            privilegedClient = client; script = nil; return
        }
        privilegedClient = nil
        let suffix = administrator ? " with administrator privileges" : ""
        let source = """
        on performCommand(arguments)
            set commandText to ""
            repeat with argument in arguments
                set commandText to commandText & quoted form of (contents of argument) & " "
            end repeat
            return do shell script commandText\(suffix)
        end performCommand
        """
        guard let script = NSAppleScript(source: source) else { throw SessionError.invalid }
        var error: NSDictionary?
        guard script.compileAndReturnError(&error) else { throw SessionError.invalid }
        self.script = script
    }
    func execute(_ arguments: [String]) -> (Int, String) {
        if let client = privilegedClient, let device, let driver {
            let operation: String
            if arguments.first == "/usr/bin/mktemp" { operation = "prepare" }
            else if arguments == ["/usr/sbin/diskutil", "unmount", device] { operation = "unmount" }
            else if arguments == ["/usr/sbin/diskutil", "mount", "readOnly", device] { operation = "recover" }
            else if arguments.first == "/bin/rmdir" { operation = "cleanup" }
            else if arguments.first == driver { operation = arguments.last?.hasSuffix("backend=fskit") == true ? "mount-fskit" : "mount-kernel" }
            else if arguments == ["--helper-commit"] { operation = "commit" }
            else { return (1, "Helper refused an unknown operation.") }
            let result = client.perform(operation)
            return (Int(result.status), result.output)
        }
        guard let script else { return (1, "Authorization host is unavailable.") }
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite),
            eventID: AEEventID(kASSubroutineEvent), targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: "performcommand"), forKeyword: AEKeyword(keyASSubroutineName))
        let values = NSAppleEventDescriptor.list()
        for (index, value) in arguments.enumerated() { values.insert(NSAppleEventDescriptor(string: value), at: index + 1) }
        let parameters = NSAppleEventDescriptor.list()
        parameters.insert(values, at: 1)
        event.setParam(parameters, forKeyword: AEKeyword(keyDirectObject))
        var error: NSDictionary?
        let result = script.executeAppleEvent(event, error: &error)
        if let error {
            let number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 1
            return (number == -128 ? 2 : 1, error[NSAppleScript.errorMessage] as? String ?? "macOS authorization failed.")
        }
        return (0, result.stringValue ?? "")
    }
}

private enum SessionError: Error { case invalid }

private func privateDirectory(_ path: String) -> Bool {
    var metadata = stat()
    guard lstat(path, &metadata) == 0 else { return false }
    return metadata.st_mode & S_IFMT == S_IFDIR && metadata.st_uid == geteuid() && metadata.st_mode & 0o777 == 0o700
}

private func readPacket(_ path: String) -> [String: Any]? {
    var metadata = stat()
    guard lstat(path, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
          metadata.st_uid == geteuid(), metadata.st_nlink == 1, metadata.st_size < 262144,
          let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
    return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
}

private func writePacket(_ value: [String: Any], _ path: String) throws {
    let data = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

private struct SessionPolicy {
    let device: String
    let driver: String
    let uid: String
    let gid: String
    var point: String?
    var driverUsed = false
    func validPoint(_ value: String) -> Bool {
        value.range(of: "^/Volumes/mountfs\\.\(device.replacingOccurrences(of: ".", with: "\\."))\\.[A-Za-z0-9]+$", options: .regularExpression) != nil
    }
    func allows(_ args: [String]) -> Bool {
        if args.count == 5, args[0] == CommandLine.arguments[0], args[1] == "--system-device-lock",
           ["acquire", "release"].contains(args[2]), args[3] == device,
           args[4].range(of: "^mountfs\\.[A-Za-z0-9]{8}$", options: .regularExpression) != nil { return true }
        if args == ["/usr/bin/mktemp", "-d", "/Volumes/mountfs.\(device).XXXXXXXX"] { return point == nil }
        if args == ["/usr/sbin/diskutil", "unmount", device] { return true }
        if args == ["/usr/sbin/diskutil", "mount", "readOnly", device] { return true }
        guard let point, validPoint(point) else { return false }
        if args == ["/bin/rmdir", point] { return true }
        let options = "rw,norecover,allow_other,default_permissions,uid=\(uid),gid=\(gid),umask=077"
        return !driverUsed && (args == [driver, "/dev/\(device)", point, "-o", options + ",local"] ||
                              args == [driver, "/dev/\(device)", point, "-o", options + ",backend=fskit"])
    }
}

private func externalNTFS(_ device: String) -> Bool {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
    process.arguments = ["info", "-plist", device]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { return false }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
          let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return false }
    return info["DeviceIdentifier"] as? String == device && info["FilesystemType"] as? String == "ntfs" &&
        info["Internal"] as? Bool == false && info["WholeDisk"] as? Bool == false
}

func authorizationSession(_ args: [String], privileged: Bool = false) -> Int32 {
    // directory, partition, driver, login uid/gid, parent core PID
    guard args.count == 6, privateDirectory(args[0]),
          args[1].range(of: "^disk[0-9]+s[0-9]+(s[0-9]+)?$", options: .regularExpression) != nil,
          ["/opt/homebrew/bin/ntfs-3g", "/usr/local/bin/ntfs-3g"].contains(args[2]),
          args[3] == String(geteuid()), args[4] == String(getegid()),
          let parent = Int32(args[5]), parent == getppid(),
          externalNTFS(args[1]), let identity = mediaIdentity(args[1]), let original = mountState(args[1]),
          let host = try? AuthorizationHost(privileged: privileged, device: args[1], driver: args[2]) else {
        FileHandle.standardError.write(Data("Cannot establish a safe external NTFS authorization session.\n".utf8))
        return 1
    }
    let directory = args[0]
    defer { try? writePacket(["ended": true], directory + "/authorization-ended.plist") }
    let request = directory + "/authorization-request.plist"
    let response = directory + "/authorization-response.plist"
    var policy = SessionPolicy(device: args[1], driver: args[2], uid: args[3], gid: args[4])
    let originalPoint = original["MountPoint"] as? String ?? ""
    let deadline = ProcessInfo.processInfo.systemUptime + 300
    while getppid() == parent && privateDirectory(directory) && ProcessInfo.processInfo.systemUptime < deadline {
        guard let packet = readPacket(request) else { Thread.sleep(forTimeInterval: 0.05); continue }
        try? FileManager.default.removeItem(atPath: request)
        guard let id = packet["id"] as? String, let command = packet["arguments"] as? [String] else { return 1 }
        var result = (1, "Authorization session refused an invalid command or changed device.")
        if !privileged, policy.allows(command), command.dropFirst().first == "--system-device-lock" {
            // Lock release changes no disk state and must work after hot unplug.
            result = host.execute(command)
        } else if (policy.allows(command) || (privileged && policy.driverUsed && command == ["--helper-commit"])), mediaIdentity(policy.device) == identity, let state = mountState(policy.device) {
            let mountedPoint = state["MountPoint"] as? String ?? ""
            let unmount = command.first == "/usr/sbin/diskutil" && command.dropFirst().first == "unmount"
            let mounting = command.first == policy.driver || command == ["/usr/sbin/diskutil", "mount", "readOnly", policy.device]
            if (!unmount || (!mountedPoint.isEmpty && (mountedPoint == originalPoint || mountedPoint == policy.point))) &&
               (!mounting || mountedPoint.isEmpty) &&
               (command.first != "/bin/rmdir" || mountedPoint != policy.point) {
                result = host.execute(command)
                if command.first == policy.driver { policy.driverUsed = true }
                if command.first == "/usr/bin/mktemp", result.0 == 0 {
                    let point = result.1.trimmingCharacters(in: .whitespacesAndNewlines)
                    if policy.validPoint(point) { policy.point = point }
                    else { result = (1, "Authorization session received an invalid mount directory.") }
                }
            }
        }
        do { try writePacket(["id": id, "status": result.0, "output": String(result.1.prefix(16000))], response) }
        catch { return 1 }
    }
    return 0
}

func authorizationRequest(_ args: [String], timeout: TimeInterval? = nil) -> Int32 {
    guard args.count >= 3, privateDirectory(args[0]), let pid = Int32(args[1]), pid > 1 else { return 1 }
    let request = args[0] + "/authorization-request.plist"
    let response = args[0] + "/authorization-response.plist"
    let id = UUID().uuidString
    do { try writePacket(["id": id, "arguments": Array(args.dropFirst(2))], request) }
    catch { return 1 }
    let deadline = ProcessInfo.processInfo.systemUptime + min(timeout ?? 300, 300)
    while privateDirectory(args[0]) && authorizationProcessIsLive(pid) {
        if ProcessInfo.processInfo.systemUptime >= deadline ||
           readPacket(args[0] + "/authorization-ended.plist")?["ended"] as? Bool == true { break }
        if let packet = readPacket(response), packet["id"] as? String == id,
           let status = packet["status"] as? Int, let output = packet["output"] as? String {
            if !output.isEmpty {
                (status == 0 ? FileHandle.standardOutput : FileHandle.standardError).write(Data((output + "\n").utf8))
            }
            return Int32(status)
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    FileHandle.standardError.write(Data("Authorization session ended; no new authorization session was started.\n".utf8))
    return 1
}

func authorizationSelfTest() -> Int32 {
    guard SystemDeviceLock.selfTest() else { return 1 }
    var policy = SessionPolicy(device: "disk6s1", driver: "/opt/homebrew/bin/ntfs-3g", uid: "501", gid: "20")
    guard policy.allows(["/usr/bin/mktemp", "-d", "/Volumes/mountfs.disk6s1.XXXXXXXX"]),
          !policy.allows(["/bin/sh", "-c", "anything"]),
          !policy.allows(["/usr/sbin/diskutil", "unmount", "disk7s1"]),
          !policy.allows(["/usr/sbin/diskutil", "mount", "disk6s1"]) else { return 1 }
    policy.point = "/Volumes/mountfs.disk6s1.test123"
    guard policy.allows(["/bin/rmdir", policy.point!]),
          !policy.allows(["/bin/rmdir", "/Volumes/other"]),
          !policy.allows([policy.driver, "/dev/disk6s1", policy.point!, "-o", "rw,force"]) else { return 1 }
    let valid = [policy.driver, "/dev/disk6s1", policy.point!, "-o", "rw,norecover,allow_other,default_permissions,uid=501,gid=20,umask=077,local"]
    guard policy.allows(valid) else { return 1 }
    policy.driverUsed = true
    guard !policy.allows(valid), let host = try? AuthorizationHost(administrator: false) else { return 1 }
    // Exercise two calls through the SAME compiled handler, without privileges.
    for value in ["spaces and 'quotes'", "$(touch not-executed); "] {
        let result = host.execute(["/usr/bin/printf", "%s", value])
        guard result.0 == 0, result.1 == value else { return 1 }
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mountfs-auth-test-" + UUID().uuidString).path
    do { try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
    catch { return 1 }
    defer { try? FileManager.default.removeItem(atPath: directory) }
    guard privateDirectory(directory) else { return 1 }
    let symlink = directory + "/symlink"
    do { try FileManager.default.createSymbolicLink(atPath: symlink, withDestinationPath: "/etc/hosts") }
    catch { return 1 }
    guard readPacket(symlink) == nil else { return 1 }
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
        defer { group.leave() }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let request = readPacket(directory + "/authorization-request.plist"), let id = request["id"] as? String {
                try? writePacket(["id": id, "status": 0, "output": "IPC round trip"], directory + "/authorization-response.plist")
                return
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
    guard authorizationRequest([directory, String(getpid()), "/usr/bin/printf", "%s", "IPC round trip"], timeout: 10) == 0 else { return 1 }
    group.wait()
    // The portable tool test also verifies the macOS zombie-state classifier.
    let start = ProcessInfo.processInfo.systemUptime
    guard authorizationRequest([directory, String(getpid()), "/usr/bin/true"], timeout: 0.1) != 0 else { return 1 }
    do { try writePacket(["ended": true], directory + "/authorization-ended.plist") } catch { return 1 }
    guard authorizationRequest([directory, String(getpid()), "/usr/bin/true"], timeout: 10) != 0,
          ProcessInfo.processInfo.systemUptime - start < 2 else { return 1 }
    print("PASS silent-live-host and ended-session requests fail within a deadline")
    print("PASS private IPC packet round trip and symlink rejection")
    print("PASS authorization allowlist, one-shot driver and persistent AppleScript argument quoting (unprivileged)")
    return 0
}
