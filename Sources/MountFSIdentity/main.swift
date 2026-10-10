import Foundation
import Darwin
import MountFSPrivileged

let arguments = CommandLine.arguments
if arguments.count == 2, arguments[1] == "--helper-status" {
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
