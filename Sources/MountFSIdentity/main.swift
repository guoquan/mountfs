import Foundation
import Darwin
import MountFSPrivileged

let arguments = CommandLine.arguments
if arguments.count == 3, arguments[1] == "--driver-approval-plan" {
    do {
        let data = try JSONSerialization.data(withJSONObject: driverApprovalPlan(arguments[2]), options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
    } catch { FileHandle.standardError.write(Data(("Driver preflight failed: \(error)\n").utf8)); exit(1) }
} else if arguments.count == 5, arguments[1] == "--prepare-approved-driver", geteuid() == 0 {
    do {
        guard let uid = UInt32(arguments[3]), uid > 0, let data = arguments[2].data(using: .utf8), data.count <= 65536,
              let hashes = (try JSONSerialization.jsonObject(with: data)) as? [String: String] else { exit(1) }
        print(try approvedDriver(arguments[4], uid: uid, hashes: hashes))
    } catch { FileHandle.standardError.write(Data(("Approved driver refused: \(error)\n").utf8)); exit(1) }
} else if arguments.count >= 2, arguments[1] == "--approved-driver-run" {
    exit(runApprovedDriver(Array(arguments.dropFirst(2))))
} else if arguments.count == 5, arguments[1] == "--root-boundary-args" {
    do {
        let boundary = try RootBoundary()
        let command = try boundary.command([arguments[0], "--system-device-lock"] + Array(arguments.dropFirst(2)))
        let data = try JSONSerialization.data(withJSONObject: command)
        FileHandle.standardOutput.write(data)
    } catch { exit(1) }
} else if arguments.count >= 3, arguments[1] == "--authorize-cli" {
    do {
        let command = Array(arguments.dropFirst(2))
        let boundary = try RootBoundary(driver: command.first == arguments[0] ? nil : command.first)
        let result = runTool("/usr/bin/sudo", ["-n", "--"] + (try boundary.command(command)), timeout: 300)
        if !result.output.isEmpty { FileHandle.standardOutput.write(Data((result.output + "\n").utf8)) }
        exit(result.status)
    } catch { FileHandle.standardError.write(Data(("Cannot authorize a protected executable: \(error)\n").utf8)); exit(1) }
} else if arguments.count == 5, arguments[1] == "--system-device-lock", ["acquire", "release"].contains(arguments[2]) {
    do {
        try SystemDeviceLock.perform(arguments[2], device: arguments[3], token: arguments[4])
        exit(0)
    } catch {
        FileHandle.standardError.write(Data(("System-wide device lock failed: \(error)\n").utf8)); exit(1)
    }
} else if arguments.count == 2, arguments[1] == "--helper-status" {
    do {
        let result = try MountHelperClient().status()
        print(result.output); exit(result.status)
    } catch { print("Helper unavailable: \(error)"); exit(1) }
} else if arguments.count == 3, arguments[1] == "--helper-configure" {
    do {
        let client = try MountHelperClient()
        let readiness = client.status()
        guard readiness.status == 0 else {
            print(readiness.output)
            print("If the app was replaced, disable and re-enable the permission helper in Settings before retrying setup. No setup authorization was requested.")
            exit(1)
        }
        guard let result = withAdministratorAuthorization({ client.configure(driver: arguments[2], authorization: $0) }) else {
            print("Helper setup authorization was cancelled or denied."); exit(2)
        }
        if result.status == 0 {
            print("Protected NTFS driver: " + result.output)
            print("Setup complete. Future helper mounts do not request a password for each subcommand. If macOS denies device access, grant Full Disk Access to this protected ntfs-3g executable; the existing Homebrew permission may not cover the copy. To pick it in the permission window, press Command-Shift-G and paste its path. Refresh the protected driver from Settings after a Homebrew driver update.")
        } else { print(result.output) }
        exit(result.status)
    } catch { print("Helper setup failed: \(error)"); exit(1) }
} else if arguments.count >= 2, arguments[1] == "--privileged-session" {
    exit(authorizationSession(Array(arguments.dropFirst(2)), privileged: true))
} else if arguments.count == 2, arguments[1] == "--authorization-self-test" {
    exit(authorizationSelfTest())
} else if arguments.count >= 2, arguments[1] == "--authorization-session" {
    exit(authorizationSession(Array(arguments.dropFirst(2))))
} else if arguments.count >= 2, arguments[1] == "--authorization-request" {
    exit(authorizationRequest(Array(arguments.dropFirst(2))))
} else if arguments.count == 3, arguments[1] == "--identity", let value = mediaIdentity(arguments[2]) {
    print(value)
} else if arguments.count == 3, arguments[1] == "--mount-state", let value = mountState(arguments[2]),
          let data = try? PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0) {
    FileHandle.standardOutput.write(data)
} else {
    FileHandle.standardError.write(Data("Cannot query current partition identity or kernel mount state.\n".utf8))
    exit(1)
}
