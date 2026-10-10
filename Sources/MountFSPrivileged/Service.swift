import Foundation
import Security

public let helperServiceName = "net.guoquan.mountfs.helper"
public let helperPlistName = helperServiceName + ".plist"

@objc public protocol MountHelperProtocol {
    func status(withReply reply: @escaping (String) -> Void)
    func configure(_ driver: String, authorization: Data, withReply reply: @escaping (Int32, String) -> Void)
    func begin(_ device: String, identity: String, withReply reply: @escaping (Int32, String) -> Void)
    func perform(_ operation: String, withReply reply: @escaping (Int32, String) -> Void)
}

public struct HelperReply {
    public let status: Int32
    public let output: String
    public init(_ status: Int32, _ output: String) { self.status = status; self.output = output }
}

private final class ReplyBox {
    private let lock = NSLock()
    private var value: HelperReply?
    private let ready = DispatchSemaphore(value: 0)
    func set(_ reply: HelperReply) {
        lock.lock()
        if value == nil { value = reply; ready.signal() }
        lock.unlock()
    }
    func wait(timeout: TimeInterval?) -> HelperReply {
        if let timeout {
            guard ready.wait(timeout: .now() + timeout) == .success else { return HelperReply(1, "Helper status check timed out.") }
        } else { ready.wait() }
        lock.lock(); defer { lock.unlock() }
        return value ?? HelperReply(1, "Helper response unavailable.")
    }
}

// Every mutation waits for an actual response or a broken connection, never a
// timeout followed by another execution path. XPC authenticates the live peer.
public final class MountHelperClient {
    private let connection: NSXPCConnection
    private let pendingLock = NSLock()
    private var pending: ReplyBox?
    private var disconnected = false
    public init() throws {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let configURL = bundle.appendingPathComponent("Contents/Resources/HelperPeers.plist")
        guard let data = try? Data(contentsOf: configURL),
              let config = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: String],
              let server = config["server"], !server.isEmpty else { throw HelperError.invalid("Bundled helper identity is missing.") }
        connection = NSXPCConnection(machServiceName: helperServiceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: MountHelperProtocol.self)
        connection.setCodeSigningRequirement(server)
        connection.invalidationHandler = { [weak self] in self?.broken() }
        connection.interruptionHandler = { [weak self] in self?.broken() }
        connection.resume()
    }
    deinit { connection.invalidate() }
    private func broken() {
        pendingLock.lock(); disconnected = true; let box = pending; pendingLock.unlock()
        box?.set(HelperReply(1, "Helper connection ended. No fallback mount was started."))
    }
    private func call(timeout: TimeInterval? = nil, _ body: (MountHelperProtocol, ReplyBox) -> Void) -> HelperReply {
        let box = ReplyBox()
        pendingLock.lock()
        guard !disconnected, pending == nil else { pendingLock.unlock(); return HelperReply(1, "Helper connection is unavailable or busy.") }
        pending = box; pendingLock.unlock()
        defer { pendingLock.lock(); pending = nil; pendingLock.unlock() }
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
            box.set(HelperReply(1, "Helper connection failed: " + error.localizedDescription))
        }) as? MountHelperProtocol else { return HelperReply(1, "Helper proxy unavailable.") }
        body(proxy, box)
        return box.wait(timeout: timeout)
    }
    public func status() -> HelperReply { call(timeout: 5) { service, box in service.status { box.set(HelperReply(0, $0)) } } }
    public func configure(driver: String, authorization: Data) -> HelperReply {
        call { service, box in service.configure(driver, authorization: authorization) { box.set(HelperReply($0, $1)) } }
    }
    public func begin(device: String, identity: String) -> HelperReply {
        call { service, box in service.begin(device, identity: identity) { box.set(HelperReply($0, $1)) } }
    }
    public func perform(_ operation: String) -> HelperReply {
        call { service, box in service.perform(operation) { box.set(HelperReply($0, $1)) } }
    }
}

public enum HelperError: Error {
    case invalid(String)
    public var message: String { switch self { case .invalid(let message): return message } }
}

public func withAdministratorAuthorization(_ body: (Data) -> HelperReply) -> HelperReply? {
    var authorization: AuthorizationRef?
    guard AuthorizationCreate(nil, nil, [], &authorization) == errAuthorizationSuccess, let authorization else { return nil }
    defer { AuthorizationFree(authorization, []) }
    return "system.privilege.admin".withCString { name in
        var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
        return withUnsafeMutablePointer(to: &item) { pointer in
            var rights = AuthorizationRights(count: 1, items: pointer)
            guard AuthorizationCopyRights(authorization, &rights, nil, [.interactionAllowed, .extendRights, .preAuthorize], nil) == errAuthorizationSuccess else { return nil }
            var external = AuthorizationExternalForm()
            guard AuthorizationMakeExternalForm(authorization, &external) == errAuthorizationSuccess else { return nil }
            return withUnsafeBytes(of: &external) { body(Data($0)) }
        }
    }
}

public func verifyAdministratorAuthorization(_ data: Data) -> Bool {
    guard data.count == MemoryLayout<AuthorizationExternalForm>.size else { return false }
    var external = AuthorizationExternalForm()
    _ = withUnsafeMutableBytes(of: &external) { buffer in data.copyBytes(to: buffer) }
    var authorization: AuthorizationRef?
    guard AuthorizationCreateFromExternalForm(&external, &authorization) == errAuthorizationSuccess, let authorization else { return false }
    defer { AuthorizationFree(authorization, []) }
    return "system.privilege.admin".withCString { name in
        var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
        return withUnsafeMutablePointer(to: &item) { pointer in
            var rights = AuthorizationRights(count: 1, items: pointer)
            // No interaction allowed in the root daemon. Setup's system dialog
            // must have already obtained the right in the user's GUI session.
            return AuthorizationCopyRights(authorization, &rights, nil, [.extendRights], nil) == errAuthorizationSuccess
        }
    }
}
