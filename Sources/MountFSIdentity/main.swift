import Foundation
import IOKit

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

let arguments = CommandLine.arguments
if arguments.count == 3, arguments[1] == "--identity", let value = mediaIdentity(arguments[2]) {
    print(value)
} else {
    FileHandle.standardError.write(Data("Cannot establish a current IOMedia partition identity.\n".utf8))
    exit(1)
}
