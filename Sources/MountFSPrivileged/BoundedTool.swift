import Foundation
import Darwin
import MountFSSystemTools

public func boundedTool(_ path: String, _ arguments: [String], timeout: TimeInterval = 30, environment: [String: String]? = nil, mergeErrors: Bool = true) -> (Int32, Data) {
    var argv = ([path] + arguments).map { strdup($0) } + [nil]
    defer { for value in argv { free(value) } }
    var envp = (environment?.sorted(by: { $0.key < $1.key }).map { strdup($0.key + "=" + $0.value) } ?? []) + [nil]
    defer { for value in envp { free(value) } }
    var output = [CChar](repeating: 0, count: 65536)
    var length = 0
    let milliseconds = UInt32(max(1, min(timeout, 300)) * 1000)
    let status = argv.withUnsafeMutableBufferPointer { values in
        output.withUnsafeMutableBufferPointer { bytes in
            envp.withUnsafeMutableBufferPointer { env in
                mountfs_run_tool_environment(path, values.baseAddress, environment == nil ? nil : env.baseAddress, mergeErrors ? 1 : 0, milliseconds, bytes.baseAddress, bytes.count, &length)
            }
        }
    }
    var data = Data(bytes: output, count: length)
    if status == 125 { data.append(Data("\nTool could not be reaped after termination; device lock must be retained.\n".utf8)) }
    if status == 124 { data.append(Data("\nTool timed out; its process group was terminated.\n".utf8)) }
    return (status, data)
}

public func authorizationProcessIsLive(_ pid: Int32) -> Bool { mountfs_process_live(pid) != 0 }

public func runningExecutableCDHash() -> String? {
    var bytes = [UInt8](repeating: 0, count: 20)
    guard mountfs_self_cdhash(&bytes) != 0 else { return nil }
    return bytes.map { String(format: "%02x", $0) }.joined()
}
