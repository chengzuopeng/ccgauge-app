// DashboardRouter.swift — choose between the local dashboard and the website.

import AppKit
import Foundation
import Network

enum DashboardRouter {
    private static let localPort: UInt16 = 3737
    private static let localHost = "127.0.0.1"

    static let localDashboardURL = URL(string: "http://localhost:3737")!
    static let websiteURL = URL(string: "https://chengzuopeng.github.io/ccgauge/")!

    static func openDashboardOrWebsite() {
        Task {
            let url = await preferredURL()
            await MainActor.run {
                _ = NSWorkspace.shared.open(url)
            }
        }
    }

    static func preferredURL() async -> URL {
        await isLocalDashboardAvailable() ? localDashboardURL : websiteURL
    }

    static func isLocalDashboardAvailable(timeout: TimeInterval = 0.45) async -> Bool {
        await isTcpPortOpen(host: localHost, port: localPort, timeout: timeout)
    }

    private static func isTcpPortOpen(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return false }

        return await withCheckedContinuation { continuation in
            let probe = PortProbe(continuation: continuation)
            let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
            probe.connection = connection

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    probe.finish(true)
                case .waiting, .failed, .cancelled:
                    probe.finish(false)
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                probe.finish(false)
            }
        }
    }
}

private final class PortProbe: @unchecked Sendable {
    var connection: NWConnection?

    private let lock = NSLock()
    private var completed = false
    private let continuation: CheckedContinuation<Bool, Never>

    init(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func finish(_ result: Bool) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        let connection = connection
        self.connection = nil
        lock.unlock()

        connection?.stateUpdateHandler = nil
        connection?.cancel()
        continuation.resume(returning: result)
    }
}
