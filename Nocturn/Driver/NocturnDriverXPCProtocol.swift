import Foundation

/// Mach service name exposed by the driver's XPC helper. Phase 7 will bundle
/// this service alongside the driver; the app connects to send per-PID volume
/// and routing updates.
public let NocturnDriverXPCMachServiceName = "com.aymandakir.nocturn.driver.xpc"

/// Contract implemented by the driver-side XPC service.
@objc(NocturnDriverXPCProtocol)
public protocol NocturnDriverXPCProtocol {
    /// Sets the linear volume (0.0 ... 1.5) for a given PID.
    func setVolume(_ volume: Float, forProcessID pid: pid_t, reply: @escaping (Bool) -> Void)

    /// Mutes or unmutes audio for a given PID.
    func setMuted(_ muted: Bool, forProcessID pid: pid_t, reply: @escaping (Bool) -> Void)

    /// Reports the installed driver version so the app can show "Update
    /// available" when the packaged version differs.
    func reportInstalledVersion(_ reply: @escaping (String) -> Void)
}

/// App-side client that wraps `NSXPCConnection` to the driver service.
public final class NocturnDriverXPCClient {
    private var connection: NSXPCConnection?

    public init() {}

    public func connect() {
        let connection = NSXPCConnection(
            machServiceName: NocturnDriverXPCMachServiceName,
            options: [.privileged]
        )
        connection.remoteObjectInterface = NSXPCInterface(with: NocturnDriverXPCProtocol.self)
        connection.resume()
        self.connection = connection
    }

    public func disconnect() {
        connection?.invalidate()
        connection = nil
    }

    public func setVolume(_ volume: Float, for pid: pid_t) async -> Bool {
        await withCheckedContinuation { continuation in
            guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ _ in
                continuation.resume(returning: false)
            }) as? NocturnDriverXPCProtocol else {
                continuation.resume(returning: false)
                return
            }
            proxy.setVolume(volume, forProcessID: pid) { success in
                continuation.resume(returning: success)
            }
        }
    }

    public func setMuted(_ muted: Bool, for pid: pid_t) async -> Bool {
        await withCheckedContinuation { continuation in
            guard let proxy = connection?.remoteObjectProxyWithErrorHandler({ _ in
                continuation.resume(returning: false)
            }) as? NocturnDriverXPCProtocol else {
                continuation.resume(returning: false)
                return
            }
            proxy.setMuted(muted, forProcessID: pid) { success in
                continuation.resume(returning: success)
            }
        }
    }
}
