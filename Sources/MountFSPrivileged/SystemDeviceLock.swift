import Foundation
import Darwin

// A root-owned directory shared by the AppleScript path and the root daemon.
// Never break a stale lock automatically: its driver may outlive its owner.
public enum SystemDeviceLock {
    private enum Failure: Error, CustomStringConvertible {
        case unsafe, busy, token
        var description: String {
            switch self {
            case .unsafe: return "Unsafe lock storage; no disk command was issued."
            case .busy: return "Another operation or a stale lock holds this device. Inspect /private/var/run/mountfs-locks as administrator; do not remove a lock until all earlier disk operations have ended."
            case .token: return "Lock ownership token does not match; lock retained."
            }
        }
    }
    public static func perform(_ operation: String, device: String, token: String) throws {
        guard geteuid() == 0 else { throw Failure.unsafe }
        try perform(operation, device: device, token: token, parent: "/private/var/run", owner: 0)
    }
    private static func trusted(_ fd: Int32, owner: uid_t, directory: Bool) -> Bool {
        var info = stat()
        return fd >= 0 && fstat(fd, &info) == 0 && info.st_uid == owner &&
            info.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG) &&
            info.st_mode & 0o022 == 0 && (directory || info.st_nlink == 1)
    }
    private static func perform(_ operation: String, device: String, token: String, parent: String, owner: uid_t) throws {
        guard ["acquire", "release"].contains(operation),
              device.range(of: "^disk[0-9]+s[0-9]+(s[0-9]+)?$", options: .regularExpression) != nil,
              token.range(of: "^[A-Za-z0-9.-]{8,80}$", options: .regularExpression) != nil else { throw Failure.unsafe }
        let parentFD = open(parent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parentFD >= 0 else { throw Failure.unsafe }
        defer { close(parentFD) }
        guard trusted(parentFD, owner: owner, directory: true) else { throw Failure.unsafe }
        if mkdirat(parentFD, "mountfs-locks", 0o700) != 0 && errno != EEXIST { throw Failure.unsafe }
        let base = openat(parentFD, "mountfs-locks", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard base >= 0 else { throw Failure.unsafe }
        defer { close(base) }
        guard trusted(base, owner: owner, directory: true) else { throw Failure.unsafe }
        if operation == "acquire", mkdirat(base, device, 0o700) != 0 { throw Failure.busy }
        let lock = openat(base, device, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard lock >= 0 else { throw Failure.unsafe }
        defer { close(lock) }
        guard trusted(lock, owner: owner, directory: true) else { throw Failure.unsafe }
        if operation == "acquire" {
            let fd = openat(lock, "owner", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw Failure.unsafe } // Retain on partial initialization.
            defer { close(fd) }
            let data = Data(token.utf8)
            let written = data.withUnsafeBytes { write(fd, $0.baseAddress!, $0.count) }
            guard written == data.count else { throw Failure.unsafe }
        } else {
            let fd = openat(lock, "owner", O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard fd >= 0 else { throw Failure.unsafe }
            defer { close(fd) }
            guard trusted(fd, owner: owner, directory: false) else { throw Failure.unsafe }
            var buffer = [UInt8](repeating: 0, count: 81)
            let count = read(fd, &buffer, buffer.count)
            guard count == token.utf8.count, String(bytes: buffer.prefix(count), encoding: .utf8) == token else { throw Failure.token }
            guard unlinkat(lock, "owner", 0) == 0, unlinkat(base, device, AT_REMOVEDIR) == 0 else { throw Failure.unsafe }
        }
    }
    public static func selfTest() -> Bool {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("mountfs-lock-test-" + UUID().uuidString).path
        do { try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        catch { return false }
        defer { try? FileManager.default.removeItem(atPath: parent) }
        func run(_ op: String, _ token: String) throws { try perform(op, device: "disk99s1", token: token, parent: parent, owner: geteuid()) }
        do {
            try run("acquire", "session-one")
            do { try run("acquire", "session-two"); return false } catch {}
            do { try run("release", "session-two"); return false } catch {}
            do { try run("acquire", "session-two"); return false } catch {}
            try run("release", "session-one")
            try run("acquire", "session-two")
            try run("release", "session-two")
            try FileManager.default.removeItem(atPath: parent + "/mountfs-locks")
            try FileManager.default.createSymbolicLink(atPath: parent + "/mountfs-locks", withDestinationPath: parent)
            do { try run("acquire", "session-one"); return false } catch {}
            print("PASS shared device lock contention, token ownership, reuse and symlink refusal")
            return true
        } catch { return false }
    }
}
