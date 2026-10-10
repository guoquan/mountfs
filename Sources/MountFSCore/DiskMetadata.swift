import Foundation

/// The diskutil plist schema uses WholeDisk, WritableVolume and MountPoint.
/// Unknown safety flags are deliberately not interpreted as external partitions.
public struct DiskMetadata {
    public let device: String
    public let name: String
    public let filesystem: String?
    public let isInternal: Bool?
    public let isWholeDisk: Bool?
    public let mountPoint: String?
    public let readOnly: Bool

    public init(_ info: [String: Any], mountState: [String: Any]? = nil, verifiedNTFS: Bool = false) {
        device = info["DeviceIdentifier"] as? String ?? "unknown"
        name = info["VolumeName"] as? String ?? device
        let reportedFilesystem = info["FilesystemType"] as? String
        let fuseTypes = ["macfuse", "fusefs", "osxfuse", "ntfs-3g"]
        filesystem = verifiedNTFS && (reportedFilesystem == nil || fuseTypes.contains(reportedFilesystem!))
            ? "ntfs" : reportedFilesystem
        isInternal = info["Internal"] as? Bool
        isWholeDisk = info["WholeDisk"] as? Bool
        let state = mountState ?? info
        let point = state["MountPoint"] as? String ?? ""
        mountPoint = point.isEmpty ? nil : point
        readOnly = !(state["WritableVolume"] as? Bool ?? false)
    }

    public var isMounted: Bool { mountPoint != nil }
    public var isExternalNTFSPartition: Bool {
        filesystem == "ntfs" && isInternal == false && isWholeDisk == false
    }

    public var exclusionReason: String {
        if isInternal == true { return "internal disk" }
        if isInternal == nil { return "missing Internal flag" }
        if isWholeDisk == true { return "whole disk (partition required)" }
        if isWholeDisk == nil { return "missing WholeDisk flag" }
        if filesystem != "ntfs" { return "filesystem: \(filesystem ?? "unrecognized")" }
        return "included"
    }
}
