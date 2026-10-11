import Foundation
import XCTest
@testable import MountFSPrivileged

final class BoundedToolTests: XCTestCase {
    func testOuterGuardPreservesCleanupWindow() {
        XCTAssertEqual(toolTimeoutMilliseconds(300), 300_000)
        XCTAssertEqual(toolTimeoutMilliseconds(420), 420_000)
        XCTAssertEqual(toolTimeoutMilliseconds(30), 30_000)
        XCTAssertEqual(toolTimeoutMilliseconds(999), 600_000)
        XCTAssertEqual(toolTimeoutMilliseconds(-1), 1_000)
        XCTAssertEqual(toolTimeoutMilliseconds(.nan), 1_000)
        XCTAssertEqual(toolTimeoutMilliseconds(.infinity), 600_000)
    }
}
