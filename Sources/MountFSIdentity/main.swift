import Foundation
import IOKit
import Darwin

// Connection-scoped identity: no raw disk handles, content reads or privileges.
// The physical IOMedia object is retained across filesystem unmount/remount.
// A disconnect/replacement creates a new registry object, even for cloned UUIDs.
func mediaIdentity(_ device: String) -> String? {
    guard device.range(of: "^disk[0-9]+s[0-9]+(s[0-9]+)?$", options: .regularExpression) != nil,
          let matching = IOBSDNameMatching(kIOMainPortDefault, 0, device) else { return nil }
    let media = IOServiceGetMatchingService(kIOMainPortDefault, matching)
    guard media != 0 else { return nil }
    defer { IOObjectRelease(media) }
    guard IOObjectConformsTo(media, "IOMedia") != 0 else { return nil }
    var unmanaged: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(media, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let properties = unmanaged?.takeRetainedValue() as? [String: Any],
          properties["BSD Name"] as? String == device,
          properties["Whole"] as? Bool == false,
          let size = properties["Size"] as? NSNumber, size.uint64Value > 0 else { return nil }
    var partitionID: UInt64 = 0
    guard IORegistryEntryGetRegistryEntryID(media, &partitionID) == KERN_SUCCESS, partitionID != 0 else { return nil }
    var current = media
    IOObjectRetain(current)
    defer { IOObjectRelease(current) }
    var parentID: UInt64 = 0
    for _ in 0..<64 {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(current, "IOService", &parent) == KERN_SUCCESS else { break }
        IOObjectRelease(current)
        current = parent
        if IOObjectConformsTo(current, "IOMedia") != 0,
           let whole = IORegistryEntryCreateCFProperty(current, "Whole" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Bool,
           whole {
            guard IORegistryEntryGetRegistryEntryID(current, &parentID) == KERN_SUCCESS else { return nil }
            break
        }
    }
    guard parentID != 0 else { return nil }
    // Refuse a service that was terminated during the metadata read.
    let stillPresent = IOServiceGetMatchingService(kIOMainPortDefault, IOBSDNameMatching(kIOMainPortDefault, 0, device))
    guard stillPresent != 0 else { return nil }
    defer { IOObjectRelease(stillPresent) }
    var checkedID: UInt64 = 0
    guard IORegistryEntryGetRegistryEntryID(stillPresent, &checkedID) == KERN_SUCCESS,
          checkedID == partitionID else { return nil }
    return "iomedia:\(partitionID):\(parentID):\(size.uint64Value)"
}

// Read the kernel mount table, not diskutil's filesystem recognition metadata.
func mountState(_ device: String) -> [String: Any]? {
    guard device.range(of: "^disk[0-9]+s[0-9]+(s[0-9]+)?$", options: .regularExpression) != nil else { return nil }
    var entries: UnsafeMutablePointer<statfs>?
    let count = getmntinfo(&entries, MNT_NOWAIT)
    guard count > 0, let entries else { return nil }
    var result: [String: Any] = ["MountPoint": "", "WritableVolume": false, "FilesystemType": "", "MountSource": ""]
    var found = false
    for index in 0..<Int(count) {
        var entry = entries[index]
        let source = withUnsafeBytes(of: &entry.f_mntfromname) { bytes in
            String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        guard source == "/dev/\(device)" || source == "/dev/r\(device)" else { continue }
        // Ambiguous duplicate mounts must never select an arbitrary path.
        guard !found else { return nil }
        found = true
        let point = withUnsafeBytes(of: &entry.f_mntonname) { bytes in
            String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        let type = withUnsafeBytes(of: &entry.f_fstypename) { bytes in
            String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        result = ["MountPoint": point, "WritableVolume": (entry.f_flags & UInt32(MNT_RDONLY)) == 0,
                  "FilesystemType": type, "MountSource": source]
    }
    return result
}

let arguments = CommandLine.arguments
if arguments.count == 2, arguments[1] == "--authorization-self-test" {
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
