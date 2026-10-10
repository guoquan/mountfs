import Foundation
import XCTest
@testable import MountFSCore

final class DiskMetadataTests: XCTestCase {
    private var ntfs: [String: Any] {
        ["DeviceIdentifier": "disk4s1", "VolumeName": "泉哥's USB", "FilesystemType": "ntfs",
         "Internal": false, "WholeDisk": false, "MountPoint": "/Volumes/泉哥's USB", "WritableVolume": false]
    }

    func testExternalNTFSWithActualPlistKeys() {
        let disk = DiskMetadata(ntfs)
        XCTAssertTrue(disk.isExternalNTFSPartition)
        XCTAssertTrue(disk.readOnly)
        XCTAssertTrue(disk.isMounted)
        XCTAssertEqual(disk.name, "泉哥's USB")
    }

    func testUnmountedAndWritableStates() {
        var info = ntfs
        info["MountPoint"] = ""
        XCTAssertFalse(DiskMetadata(info).isMounted)
        info.removeValue(forKey: "MountPoint")
        XCTAssertNil(DiskMetadata(info).mountPoint)
        info["WritableVolume"] = true
        XCTAssertFalse(DiskMetadata(info).readOnly)
    }

    func testUnsafeOrNonNTFSDevicesAreExcluded() {
        var info = ntfs
        info["Internal"] = true
        XCTAssertFalse(DiskMetadata(info).isExternalNTFSPartition)
        info = ntfs; info["WholeDisk"] = true
        XCTAssertFalse(DiskMetadata(info).isExternalNTFSPartition)
        info = ntfs; info["FilesystemType"] = "exfat"
        XCTAssertFalse(DiskMetadata(info).isExternalNTFSPartition)
        info = ntfs; info.removeValue(forKey: "WholeDisk")
        XCTAssertFalse(DiskMetadata(info).isExternalNTFSPartition)
        XCTAssertEqual(DiskMetadata(info).exclusionReason, "missing WholeDisk flag")
    }

    func testMissingWritableFlagIsConservative() {
        var info = ntfs
        info.removeValue(forKey: "WritableVolume")
        XCTAssertTrue(DiskMetadata(info).readOnly)
    }

    func testKernelMountStateOverridesDiskutilForMenu() {
        let state: [String: Any] = ["MountPoint": "/Volumes/mountfs.disk4s1.test", "WritableVolume": true]
        let disk = DiskMetadata(ntfs, mountState: state)
        XCTAssertFalse(disk.readOnly)
        XCTAssertEqual(disk.mountPoint, "/Volumes/mountfs.disk4s1.test")
        XCTAssertTrue(disk.isExternalNTFSPartition)
        let absent = DiskMetadata(ntfs, mountState: ["MountPoint": "", "WritableVolume": false])
        XCTAssertFalse(absent.isMounted)
        XCTAssertTrue(absent.readOnly)
    }

    func testOnlyVerifiedNTFSIdentityKeepsFUSEVolumeInMenu() {
        var info = ntfs
        info["FilesystemType"] = "macfuse"
        XCTAssertFalse(DiskMetadata(info).isExternalNTFSPartition)
        XCTAssertTrue(DiskMetadata(info, verifiedNTFS: true).isExternalNTFSPartition)
        info.removeValue(forKey: "FilesystemType")
        XCTAssertTrue(DiskMetadata(info, verifiedNTFS: true).isExternalNTFSPartition)
        info["Internal"] = true
        XCTAssertFalse(DiskMetadata(info, verifiedNTFS: true).isExternalNTFSPartition)
        info = ntfs; info["FilesystemType"] = "exfat"
        XCTAssertFalse(DiskMetadata(info, verifiedNTFS: true).isExternalNTFSPartition)
        info["FilesystemType"] = "macfuse"; info["WholeDisk"] = true
        XCTAssertFalse(DiskMetadata(info, verifiedNTFS: true).isExternalNTFSPartition)
    }

    func testLiveMacOSSchema() throws {
        #if os(macOS)
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", "/"]
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let info = try XCTUnwrap(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        XCTAssertNotNil(info["WholeDisk"] as? Bool)
        XCTAssertNotNil(info["WritableVolume"] as? Bool)
        let disk = DiskMetadata(info)
        XCTAssertTrue(disk.isMounted)
        XCTAssertEqual(disk.mountPoint, "/")
        XCTAssertEqual(disk.isWholeDisk, false)
        XCTAssertEqual(disk.readOnly, !(info["WritableVolume"] as! Bool))
        #else
        throw XCTSkip("Requires macOS diskutil")
        #endif
    }
}
