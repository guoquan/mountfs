import Foundation
import Darwin
import MountFSPrivileged
import MountFSSystemTools

// Real kernel peer credentials and real subprocess ancestry; no disk operation.
func authorizationIPCSelfTest() -> Bool {
    let directory = "/tmp/mountfs-ipc-" + UUID().uuidString
    do { try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
    catch { return false }
    defer { try? FileManager.default.removeItem(atPath: directory) }
    let listener = mountfs_auth_listen(directory + "/s")
    guard listener >= 0 else { return false }
    defer { close(listener) }
    let parent = getpid(), birth = mountfs_process_birth(getpid())
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async {
        defer { group.leave() }
        var index = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        while index < 4 && ProcessInfo.processInfo.systemUptime < deadline {
            let fd = mountfs_auth_accept(listener)
            if fd < 0 { Thread.sleep(forTimeInterval: 0.01); continue }
            defer { close(fd) }
            index += 1
            // First connection is this same-UID process, not its descendant.
            guard index == 4 || (mountfs_auth_peer(fd, 0, parent, birth) != 0 &&
                  mountfs_auth_peer(fd, 0, parent, birth + 1) == 0),
                  readConnection(fd, timeout: 1) != nil else { continue }
            if index == 4 { Thread.sleep(forTimeInterval: 0.3); continue }
            _ = writeConnection(["status": index == 2 ? 125 : 0, "output": "Authenticated round trip"], fd)
        }
    }
    let args = [directory, String(parent), "/usr/bin/true"]
    // Learning the directory and PID does not authorize an unrelated process.
    let rejected = authorizationRequest(args, timeout: 1) != 0
    let client = CommandLine.arguments[0]
    let reply = boundedTool(client, ["--authorization-request"] + args, timeout: 3)
    let accepted = reply.0 == 125 && String(data: reply.1, encoding: .utf8)?.contains("Authenticated round trip") == true
    func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    // Command substitution creates a legitimate nested shell in production.
    let command = ([client, "--authorization-request"] + args).map(quote).joined(separator: " ") + "; result=$?; exit $result"
    let nested = boundedTool("/bin/sh", ["-c", command], timeout: 3).0 == 0
    let start = ProcessInfo.processInfo.systemUptime
    let timeout = authorizationRequest(args, timeout: 0.1) != 0
    group.wait()
    guard rejected, accepted, nested, timeout, ProcessInfo.processInfo.systemUptime - start < 2 else { return false }
    print("PASS same-UID unrelated requester and wrong ancestor birth rejected; direct and nested shell children accepted")
    print("PASS authenticated socket round trip preserves 125; silent connection fails within deadline")
    return true
}
