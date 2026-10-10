import Foundation
import Darwin
import CryptoKit
import MountFSPrivileged

let driverSandboxProfile = "(version 1)(allow default)(deny file-read-data (subpath \"/opt/homebrew\") (subpath \"/usr/local\") (subpath \"/Users\"))"

let helperStorage = "/Library/Application Support/mouNTFS"

func rootDirectory(_ path: String) -> Bool {
    var value = stat()
    return lstat(path, &value) == 0 && value.st_mode & S_IFMT == S_IFDIR &&
        value.st_uid == 0 && value.st_mode & 0o022 == 0
}

func rootFile(_ path: String) -> Bool {
    var value = stat()
    return lstat(path, &value) == 0 && value.st_mode & S_IFMT == S_IFREG &&
        value.st_uid == 0 && value.st_mode & 0o022 == 0 && value.st_nlink == 1
}

func secureAncestors(_ path: String) -> Bool {
    var directory = URL(fileURLWithPath: path).deletingLastPathComponent()
    while true {
        guard rootDirectory(directory.path) else { return false }
        if directory.path == "/" { return true }
        directory.deleteLastPathComponent()
    }
}

func runTool(_ path: String, _ args: [String]) -> HelperReply {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "C", "HOME": "/var/root"]
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output
    process.standardError = output
    do {
        try process.run()
        // Drain continuously even after the diagnostic output limit is reached.
        var data = Data()
        while true {
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            if data.count < 65536 { data.append(chunk.prefix(65536 - data.count)) }
        }
        process.waitUntilExit()
        return HelperReply(process.terminationStatus, String(decoding: data, as: UTF8.self))
    } catch { return HelperReply(1, error.localizedDescription) }
}

func requireTool(_ path: String, _ args: [String]) throws -> String {
    let value = runTool(path, args)
    guard value.status == 0 else { throw HelperError.invalid(value.output) }
    return value.output
}

struct DriverConfiguration {
    let uid: uid_t
    let source: String
    let executable: String
    static func load() -> DriverConfiguration? {
        let path = helperStorage + "/driver.plist"
        guard rootFile(path), secureAncestors(path), let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let value = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              let uid = value["uid"] as? UInt32, uid > 0,
              let source = value["source"] as? String,
              let executable = value["executable"] as? String,
              executable.hasPrefix(helperStorage + "/driver-"), executable.hasSuffix("/ntfs-3g"),
              rootFile(executable), secureAncestors(executable) else { return nil }
        return DriverConfiguration(uid: uid, source: source, executable: executable)
    }
}

// Setup authorizes trusting one existing NTFS driver. Copy its non-system Mach-O
// dependencies into a new root-owned generation and rewrite load commands. The
// persistent daemon never executes mutable Homebrew files or caller-selected
// paths. Previous generations are retained to avoid breaking mounted drivers.
func configureDriver(_ source: String, uid: uid_t) throws -> String {
    guard ["/opt/homebrew/bin/ntfs-3g", "/usr/local/bin/ntfs-3g"].contains(source), uid > 0 else {
        throw HelperError.invalid("Only the installed Homebrew ntfs-3g driver can be selected.")
    }
    guard secureAncestors(helperStorage) else { throw HelperError.invalid("Helper storage ancestors are not protected.") }
    if !FileManager.default.fileExists(atPath: helperStorage) {
        try FileManager.default.createDirectory(atPath: helperStorage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
    }
    guard rootDirectory(helperStorage) else { throw HelperError.invalid("Helper storage is not root-owned and protected.") }
    let generation = helperStorage + "/driver-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: generation, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o755])
    var committed = false
    defer { if !committed { try? FileManager.default.removeItem(atPath: generation) } }
    var copies: [String: String] = [:]
    var edges: [String: [(String, String)]] = [:]
    var totalBytes = 0
    let executableSource = URL(fileURLWithPath: source).resolvingSymlinksInPath().path
    let executableDirectory = URL(fileURLWithPath: executableSource).deletingLastPathComponent().path

    func allowedSource(_ path: String) -> Bool {
        path.hasPrefix("/opt/homebrew/") || path.hasPrefix("/usr/local/")
    }
    func protectedSystem(_ path: String) -> Bool {
        if path.hasPrefix("/usr/lib/") || path.hasPrefix("/System/Library/") { return true }
        return path.hasPrefix("/Library/Filesystems/macfuse.fs/") && rootFile(path) && secureAncestors(path)
    }
    func dependencies(_ file: String) throws -> [String] {
        let output = try requireTool("/usr/bin/otool", ["-L", file])
        return output.components(separatedBy: .newlines).dropFirst().compactMap { line in
            guard let end = line.range(of: " (compatibility version") else { return nil }
            return String(line[..<end.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
    }
    func copyBinary(_ original: String, executable: Bool = false) throws -> String {
        let canonical = URL(fileURLWithPath: original).resolvingSymlinksInPath().path
        if let existing = copies[canonical] { return existing }
        guard allowedSource(canonical), copies.count < 64 else { throw HelperError.invalid("Unsupported driver dependency: " + canonical) }
        var metadata = stat()
        guard lstat(canonical, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size > 0, metadata.st_size <= 64 * 1024 * 1024 else { throw HelperError.invalid("Invalid driver binary: " + canonical) }
        let bytes = try Data(contentsOf: URL(fileURLWithPath: canonical))
        totalBytes += bytes.count
        guard totalBytes <= 256 * 1024 * 1024 else { throw HelperError.invalid("Driver dependency size limit exceeded.") }
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let destination = generation + "/" + (executable ? "ntfs-3g" : hash + ".dylib")
        try bytes.write(to: URL(fileURLWithPath: destination), options: .withoutOverwriting)
        guard chmod(destination, 0o755) == 0 else { throw HelperError.invalid("Cannot protect driver copy.") }
        copies[canonical] = destination
        let loadInfo = try requireTool("/usr/bin/otool", ["-l", destination])
        let lines = loadInfo.components(separatedBy: .newlines)
        var rpaths: [String] = []
        for index in lines.indices where lines[index].contains("cmd LC_RPATH") {
            for line in lines.dropFirst(index + 1).prefix(3) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("path "), let end = trimmed.range(of: " (offset") {
                    rpaths.append(String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 5)..<end.lowerBound]))
                }
            }
        }
        let loader = URL(fileURLWithPath: canonical).deletingLastPathComponent().path
        func expand(_ path: String) -> String {
            path.replacingOccurrences(of: "@loader_path", with: loader)
                .replacingOccurrences(of: "@executable_path", with: executableDirectory)
        }
        var changes: [(String, String)] = []
        for dependency in try dependencies(destination) {
            var resolved = expand(dependency)
            if dependency.hasPrefix("@rpath/") {
                let suffix = String(dependency.dropFirst(7))
                guard let found = rpaths.map({ expand($0) + "/" + suffix }).first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                    throw HelperError.invalid("Unresolved driver dependency: " + dependency)
                }
                resolved = found
            }
            guard resolved.hasPrefix("/") else { throw HelperError.invalid("Relative driver dependency refused.") }
            resolved = URL(fileURLWithPath: resolved).resolvingSymlinksInPath().path
            if resolved == canonical { continue } // dylib's own LC_ID_DYLIB
            if protectedSystem(resolved) {
                if dependency != resolved { changes.append((dependency, resolved)) }
                continue
            }
            changes.append((dependency, try copyBinary(resolved)))
        }
        edges[destination] = changes
        return destination
    }
    let driver = try copyBinary(executableSource, executable: true)
    for destination in copies.values {
        for (old, new) in edges[destination] ?? [] {
            _ = try requireTool("/usr/bin/install_name_tool", ["-change", old, new, destination])
        }
        // Remove search paths to user-writable dependency directories after
        // resolving all linked @rpath dependencies into protected copies.
        let info = try requireTool("/usr/bin/otool", ["-l", destination]).components(separatedBy: .newlines)
        for index in info.indices where info[index].contains("cmd LC_RPATH") {
            for line in info.dropFirst(index + 1).prefix(3) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("path "), let end = trimmed.range(of: " (offset") {
                    let path = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 5)..<end.lowerBound])
                    _ = try requireTool("/usr/bin/install_name_tool", ["-delete_rpath", path, destination])
                }
            }
        }
        _ = try requireTool("/usr/bin/codesign", ["--force", "--sign", "-", destination])
        guard rootFile(destination), secureAncestors(destination) else { throw HelperError.invalid("Driver copy is not protected.") }
    }
    let plist: [String: Any] = ["uid": uid, "source": source, "executable": driver]
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: URL(fileURLWithPath: helperStorage + "/driver.plist"), options: .atomic)
    guard chmod(helperStorage + "/driver.plist", 0o600) == 0 else { throw HelperError.invalid("Cannot protect helper configuration.") }
    committed = true
    return driver
}
