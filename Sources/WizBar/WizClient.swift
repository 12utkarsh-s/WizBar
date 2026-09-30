import Foundation
import Network

/// Snapshot of a bulb's state as reported by `getPilot`.
struct Pilot: Sendable {
    var state: Bool
    var dimming: Int?
    var temp: Int?
    var r: Int?
    var g: Int?
    var b: Int?
}

/// Minimal WiZ UDP client (port 38899, JSON request/response).
enum WizClient {
    private static let port: NWEndpoint.Port = 38899
    private static let queue = DispatchQueue(label: "WizBar.udp")

    static func getPilot(_ host: String) async -> Pilot? {
        let message = Data(#"{"method":"getPilot","params":{}}"#.utf8)
        guard let reply = await request(host, message),
              let obj = try? JSONSerialization.jsonObject(with: reply) as? [String: Any],
              let result = obj["result"] as? [String: Any]
        else { return nil }

        return Pilot(
            state: result["state"] as? Bool ?? false,
            dimming: result["dimming"] as? Int,
            temp: result["temp"] as? Int,
            r: result["r"] as? Int,
            g: result["g"] as? Int,
            b: result["b"] as? Int
        )
    }

    static func setPilotMessage(_ params: [String: Any]) -> Data {
        let message: [String: Any] = ["id": 1, "method": "setPilot", "params": params]
        return (try? JSONSerialization.data(withJSONObject: message)) ?? Data()
    }

    /// Sends a prebuilt setPilot message; returns true if the bulb acknowledged it.
    @discardableResult
    static func setPilot(_ host: String, message: Data) async -> Bool {
        guard let reply = await request(host, message),
              let obj = try? JSONSerialization.jsonObject(with: reply) as? [String: Any]
        else { return false }
        return obj["error"] == nil
    }

    /// Sends one datagram and waits for a single reply, or nil on timeout/failure.
    private static func request(_ host: String, _ data: Data, timeout: TimeInterval = 1.0) async -> Data? {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .udp)
            let once = Once()
            let finish: @Sendable (Data?) -> Void = { reply in
                once.run {
                    connection.cancel()
                    continuation.resume(returning: reply)
                }
            }

            connection.stateUpdateHandler = { state in
                if case .failed = state { finish(nil) }
            }
            connection.start(queue: queue)
            connection.send(content: data, completion: .contentProcessed { error in
                if error != nil { finish(nil) }
            })
            connection.receiveMessage { reply, _, _, _ in finish(reply) }
            queue.asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }
}

/// Runs its closure at most once, from any thread.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}
