import Foundation
import Darwin
import Carbon
import MountFSPrivileged
import MountFSSystemTools

// This host stays UNPRIVILEGED. One NSAppleScript instance owns the OS-managed
// authorization cache. Requests are bounded to this one partition/transaction.
private final class AuthorizationHost {
    private let script: NSAppleScript?
    private var boundary: RootBoundary?
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
        if administrator { boundary = try RootBoundary(driver: driver) }
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
        var approvedArguments = arguments
        if let boundary, arguments.first == CommandLine.arguments[0] || arguments.first == driver {
            do { approvedArguments = try boundary.command(arguments) }
            catch { return (1, "Privileged executable validation failed: \(error)") }
        }
        let values = NSAppleEventDescriptor.list()
        for (index, value) in approvedArguments.enumerated() { values.insert(NSAppleEventDescriptor(string: value), at: index + 1) }
        let parameters = NSAppleEventDescriptor.list()
        parameters.insert(values, at: 1)
        event.setParam(parameters, forKeyword: AEKeyword(keyDirectObject))
        var error: NSDictionary?
        let result = script.executeAppleEvent(event, error: &error)
        if let error {
            let number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 1
            return (number == -128 ? 2 : (number == 125 ? 125 : 1), error[NSAppleScript.errorMessage] as? String ?? "macOS authorization failed.")
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

func readConnection(_ fd: Int32, timeout: TimeInterval) -> [String: Any]? {
    var bytes = [CChar](repeating: 0, count: 262144)
    var count = 0
    guard mountfs_auth_read(fd, &bytes, bytes.count, &count, UInt32(max(1, min(timeout, 300) * 1000))) != 0 else { return nil }
    return (try? PropertyListSerialization.propertyList(from: Data(bytes: bytes, count: count), format: nil)) as? [String: Any]
}
func writeConnection(_ value: [String: Any], _ fd: Int32) -> Bool {
    guard let data = try? PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0) else { return false }
    return data.withUnsafeBytes { bytes in
        mountfs_auth_write(fd, bytes.bindMemory(to: CChar.self).baseAddress, data.count, 1000) != 0
    }
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
    let birth = mountfs_process_birth(parent)
    let socketPath = directory + "/s"
    let listener = mountfs_auth_listen(socketPath)
    guard birth != 0, listener >= 0 else { return 1 }
    defer { close(listener); unlink(socketPath) }
    var policy = SessionPolicy(device: args[1], driver: args[2], uid: args[3], gid: args[4])
    var terminationUnconfirmed = false
    let originalPoint = original["MountPoint"] as? String ?? ""
    let deadline = ProcessInfo.processInfo.systemUptime + 300
    while getppid() == parent && privateDirectory(directory) && ProcessInfo.processInfo.systemUptime < deadline {
        let connection = mountfs_auth_accept(listener)
        guard connection >= 0 else { Thread.sleep(forTimeInterval: 0.05); continue }
        defer { close(connection) }
        guard mountfs_auth_peer(connection, 0, parent, birth) != 0,
              let packet = readConnection(connection, timeout: 1),
              let command = packet["arguments"] as? [String],
              mountfs_auth_peer(connection, 0, parent, birth) != 0 else { continue }
        var result = (1, "Authorization session refused an invalid command or changed device.")
        if terminationUnconfirmed {
            result = (125, "Earlier operation termination is unconfirmed; device lock retained and further mutation refused.")
        } else if !privileged, policy.allows(command), command.dropFirst().first == "--system-device-lock" {
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
        // A disconnected requester never changes the transport into a reusable file.
        if result.0 == 125 { terminationUnconfirmed = true }
        if !writeConnection(["status": result.0, "output": String(result.1.prefix(16000))], connection) { terminationUnconfirmed = true }
    }
    return 0
}

func authorizationRequest(_ args: [String], timeout: TimeInterval? = nil) -> Int32 {
    guard args.count >= 3, privateDirectory(args[0]), let pid = Int32(args[1]), pid > 1 else { return 1 }
    let deadline = ProcessInfo.processInfo.systemUptime + min(timeout ?? 300, 300)
    var connection: Int32 = -1
    while privateDirectory(args[0]) && authorizationProcessIsLive(pid) && ProcessInfo.processInfo.systemUptime < deadline {
        connection = mountfs_auth_connect(args[0] + "/s")
        if connection >= 0 { break }
        Thread.sleep(forTimeInterval: 0.05)
    }
    guard connection >= 0 else { return 1 }
    defer { close(connection) }
    guard mountfs_auth_peer(connection, pid, 0, 0) != 0,
          writeConnection(["arguments": Array(args.dropFirst(2))], connection),
          let packet = readConnection(connection, timeout: max(0, deadline - ProcessInfo.processInfo.systemUptime)),
          let status = packet["status"] as? Int, let output = packet["output"] as? String else {
        FileHandle.standardError.write(Data("Authorization connection ended or timed out; no new authorization session was started.\n".utf8))
        // The peer might still be executing an already accepted request.
        return 125
    }
    if !output.isEmpty {
        (status == 0 ? FileHandle.standardOutput : FileHandle.standardError).write(Data((output + "\n").utf8))
    }
    return Int32(status)
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
    // AppleScript must preserve the lock-retaining status from the root tool.
    guard host.execute(["/bin/sh", "-c", "exit 125"]).0 == 125 else { return 1 }
    guard authorizationIPCSelfTest() else { return 1 }
    print("PASS authorization allowlist, one-shot driver and persistent AppleScript argument quoting (unprivileged)")
    return 0
}
