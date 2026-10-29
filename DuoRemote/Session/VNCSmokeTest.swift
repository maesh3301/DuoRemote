#if DEBUG
import Foundation

/// `-vncSmoke <host>`: connect with no credentials and log state changes plus the requested auth
/// type as `[smoke]` lines on stdout. Proves tailnet + RFB handshake + auth negotiation without a
/// password (the connection then fails with "no authentication data", as expected).
enum VNCSmokeTest {
    private static var session: VNCSession?

    static func run(host: String) {
        let log: @Sendable (String) -> Void = { line in
            print("[smoke] \(line)")
            fflush(stdout)
        }
        log("connecting to \(host):5900")
        let s = VNCSession(hostname: host)
        session = s
        s.connect(credentials: nil, log: log)
    }

    /// `-tailscaleSmoke <host>`: the same through built-in Tailscale (turned on and signed in).
    static func runEmbedded(host: String) {
        let log: @Sendable (String) -> Void = { line in
            print("[smoke] \(line)")
            fflush(stdout)
        }
        Task {
            let tailscale = EmbeddedTailscale.shared
            tailscale.start()
            switch await tailscale.route(to: host) {
            case .failure(let problem):
                log("route failed: \(problem.message)")
            case .success(let address):
                log("route ok, connecting to \(host):5900 through built-in Tailscale")
                let s = VNCSession(hostname: host)
                session = s
                s.connect(credentials: nil, socket: tailscale.socketProvider(address: address, port: 5900, name: host), log: log)
            }
        }
    }
}
#endif
