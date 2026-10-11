import Foundation

/// New work expires before the bounded recovery/completion window ends.
public struct AuthorizationLifetime {
    public let operationDeadline: TimeInterval
    public let cleanupDeadline: TimeInterval
    public init(start: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        operationDeadline = start + 300
        cleanupDeadline = start + 420
    }
    public func allows(cleanup: Bool, at now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        now < (cleanup ? cleanupDeadline : operationDeadline)
    }
}
