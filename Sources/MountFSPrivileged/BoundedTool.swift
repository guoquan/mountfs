import Foundation
import Darwin
import MountFSSystemTools

public func boundedTool(_ path: String, _ arguments: [String], timeout: TimeInterval = 30) -> (Int32, Data) {
    var argv = ([path] + arguments).map { strdup($0) } + [nil]
    defer { for value in argv { free(value) } }
    var output = [CChar](repeating: 0, count: 65536)
    var length = 0
    let milliseconds = UInt32(max(1, min(timeout, 300)) * 1000)
    let status = argv.withUnsafeMutableBufferPointer { values in
        output.withUnsafeMutableBufferPointer { bytes in
            mountfs_run_tool(path, values.baseAddress, milliseconds, bytes.baseAddress, bytes.count, &length)
        }
    }
    var data = Data(bytes: output, count: length)
    if status == 125 { data.append(Data("\nTool could not be reaped after termination; device lock must be retained.\n".utf8)) }
    if status == 124 { data.append(Data("\nTool timed out; its process group was terminated.\n".utf8)) }
    return (status, data)
}

public func authorizationProcessIsLive(_ pid: Int32) -> Bool { mountfs_process_live(pid) != 0 }
