@preconcurrency import RoyalVNCKit
import Foundation
import Observation
import OSLog
import TailscaleKit
import UIKit

/// The parts of the tunnel's status JSON the app reads. Every field is optional: tailscaled adds and
/// drops fields between versions, and TailscaleKit's own typed models already fail to decode them.
nonisolated struct EmbeddedTailnetStatus: Decodable, Equatable, Sendable {
    struct Node: Decodable, Equatable, Sendable {
        var hostName: String?
        var dnsName: String?
        var addresses: [String]?
        var online: Bool?

        enum CodingKeys: String, CodingKey {
            case hostName = "HostName", dnsName = "DNSName", addresses = "TailscaleIPs", online = "Online"
        }
    }

    var backendState: String?
    var authURL: String?
    var ownNode: Node?
    var peers: [String: Node]?

    enum CodingKeys: String, CodingKey {
        case backendState = "BackendState", authURL = "AuthURL", ownNode = "Self", peers = "Peer"
    }
}

/// Finding a Mac in the tunnel's peer list. Pure, so it can be tested.
nonisolated enum EmbeddedTailnet {
    /// The Mac called `name`: its MagicDNS name (short or full), its machine name, or one of its
    /// Tailscale addresses. Only peers of the tunnel count, so nothing outside the tailnet can match.
    static func peer(named name: String, in peers: [EmbeddedTailnetStatus.Node]) -> EmbeddedTailnetStatus.Node? {
        let wanted = normalized(name)
        guard !wanted.isEmpty else { return nil }
        if Tailnet.isTailscaleAddress(wanted) {
            return peers.first { ($0.addresses ?? []).contains(wanted) }
        }
        let byDNS = peers.first { peer in
            guard let dns = peer.dnsName.map(normalized), !dns.isEmpty else { return false }
            return dns == wanted || dns.split(separator: ".").first.map(String.init) == wanted
        }
        return byDNS ?? peers.first { $0.hostName.map(normalized) == wanted }
    }

    /// The address to dial: IPv4 if there is one.
    static func address(of peer: EmbeddedTailnetStatus.Node) -> String? {
        let addresses = (peer.addresses ?? []).filter(Tailnet.isTailscaleAddress)
        return addresses.first { !$0.contains(":") } ?? addresses.first
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "[]")))
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}

/// DuoRemote's own Tailscale node, so a Mac can be reached without the Tailscale app's VPN.
/// The node runs in the app (userspace, no VPN profile) and shows up in the tailnet as "duoremote".
@Observable
final class EmbeddedTailscale {
    static let shared = EmbeddedTailscale()

    enum State: Equatable {
        case off, starting, needsLogin, running
        case failed(String)
    }

    nonisolated enum Problem: Error, Equatable {
        case notSignedIn, notFound(String), offline(String), unreachable(String)

        var message: String {
            switch self {
            case .notSignedIn: "Built-in Tailscale isn't signed in. Sign in under Settings → Built-in Tailscale."
            case .notFound(let name): "Can't find \(name) in your tailnet."
            case .offline(let name): "\(name) is offline in your tailnet."
            case .unreachable(let name): "Can't reach \(name) through built-in Tailscale."
            }
        }
    }

    private(set) var state: State = .off
    private(set) var loginURL: URL?
    private(set) var ownAddress: String?
    private(set) var peers: [EmbeddedTailnetStatus.Node] = []

    /// Running and the coordination server has sent the peer list. A node that has just started
    /// reports Running from its saved state a moment before it knows any peers.
    var hasPeerList: Bool { state == .running && !peers.isEmpty }

    /// Remembered so the node starts with the app once the user has turned it on.
    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    @ObservationIgnored private var node: TailscaleNode?
    @ObservationIgnored private var handle: TailscaleHandle?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var openLoginWhenReady = false

    private static let enabledKey = "embeddedTailscale"
    nonisolated private static let log = Logger(subsystem: AppInfo.bundleID, category: "tailscale")

    // MARK: Lifecycle

    func startIfEnabled() {
        if isEnabled { start() }
    }

    /// Starts the node. A node that isn't signed in yet asks for a browser sign-in; with
    /// `openLogin`, that page opens as soon as the sign-in link arrives.
    func start(openLogin: Bool = false) {
        if openLogin { openLoginWhenReady = true }
        if state == .needsLogin, openLogin, let loginURL { open(loginURL) }
        guard node == nil, state != .starting else { return }
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        state = .starting
        Task {
            do {
                let node = try await Task.detached(priority: .userInitiated) { try Self.makeNode() }.value
                self.node = node
                handle = await node.tailscale
                // Blocks until signed in; the poll below reports progress meanwhile.
                Task.detached { do { try await node.up() } catch { Self.log.error("up failed: \(error.localizedDescription, privacy: .public)") } }
                poll()
            } catch {
                Self.log.error("start failed: \(error.localizedDescription, privacy: .public)")
                state = .failed("Built-in Tailscale couldn't start.")
            }
        }
    }

    /// Signs out by discarding this node's keys. Its entry stays in the Tailscale admin console
    /// until it's removed there or expires.
    func signOut() async {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        pollTask?.cancel()
        pollTask = nil
        if let node { try? await node.close() }
        node = nil
        handle = nil
        state = .off
        loginURL = nil
        ownAddress = nil
        peers = []
        openLoginWhenReady = false
        if let dir = try? Self.stateDirectory(create: false) { try? FileManager.default.removeItem(at: dir) }
    }

    nonisolated private static func makeNode() throws -> TailscaleNode {
        let config = Configuration(hostName: "duoremote", path: try stateDirectory(create: true).path(percentEncoded: false),
                                   authKey: nil, controlURL: kDefaultControlURL, ephemeral: false)
        return try TailscaleNode(config: config, logger: QuietSink())
    }

    /// The node's keys and state: kept out of backups, readable only after the first unlock.
    nonisolated private static func stateDirectory(create: Bool) throws -> URL {
        var dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: create)
            .appending(path: "Tailscale", directoryHint: .isDirectory)
        if create {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try dir.setResourceValues(values)
        }
        return dir
    }

    // MARK: Status

    /// Polls often while starting or signing in, then occasionally to keep the peer list fresh.
    private func poll() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: hasPeerList ? .seconds(15) : .seconds(1))
            }
        }
    }

    /// Reads the node's status now.
    func refresh() async {
        guard let node else { return }
        guard let data = try? await node.statusJSON(),
              let status = try? JSONDecoder().decode(EmbeddedTailnetStatus.self, from: data) else { return }
        guard self.node === node else { return }   // signed out meanwhile
        apply(status)
    }

    private func apply(_ status: EmbeddedTailnetStatus) {
        peers = status.peers.map { Array($0.values) } ?? []
        ownAddress = status.ownNode.flatMap(EmbeddedTailnet.address(of:))
        switch status.backendState {
        case "Running":
            state = .running
            loginURL = nil
            openLoginWhenReady = false
        case "NeedsLogin", "NeedsMachineAuth":
            state = .needsLogin
            loginURL = status.authURL.flatMap { $0.isEmpty ? nil : URL(string: $0) }
            if openLoginWhenReady, let loginURL {
                openLoginWhenReady = false
                open(loginURL)
            }
        default:
            if state != .needsLogin { state = .starting }
        }
    }

    private func open(_ url: URL) {
        UIApplication.shared.open(url)
    }

    // MARK: Connecting

    /// The checked Tailscale address of the Mac called `hostname`. Starts the node if it's turned on
    /// but not running yet, and waits briefly for it and its peer list.
    func route(to hostname: String) async -> Result<String, Problem> {
        guard isEnabled else { return .failure(.notSignedIn) }
        await waitForPeerList()
        guard state == .running else { return .failure(.notSignedIn) }
        guard let peer = EmbeddedTailnet.peer(named: hostname, in: peers),
              let address = EmbeddedTailnet.address(of: peer) else { return .failure(.notFound(hostname)) }
        if peer.online == false { return .failure(.offline(hostname)) }
        return .success(address)
    }

    /// Starts the node if needed and waits (up to 15 s) until it is signed out or has its peer list,
    /// then reads the status once more so the list is current.
    private func waitForPeerList() async {
        if node == nil { start() }
        await refresh()
        let deadline = ContinuousClock.now + .seconds(15)
        while !hasPeerList, state != .needsLogin, ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
            await refresh()
        }
        if hasPeerList { await refresh() }
    }

    // MARK: Warming up

    @ObservationIgnored private var warmedAt: [String: ContinuousClock.Instant] = [:]
    #if DEBUG
    /// `-noWarmUp`, to time a connect without it.
    static var warmUpDisabled = false
    #endif

    /// Pings these Macs through the node, so the next connect finds the direct path and a
    /// WireGuard session already set up instead of starting over Tailscale's relays. A few small
    /// packets per online Mac, at most every 30 s; the path goes cold after about a minute idle.
    func warmUp(_ hostnames: [String]) async {
        #if DEBUG
        if Self.warmUpDisabled { return }
        #endif
        guard isEnabled, !hostnames.isEmpty else { return }
        await waitForPeerList()
        guard hasPeerList, let node else { return }
        let now = ContinuousClock.now
        var targets: [String] = []
        for name in hostnames {
            guard let peer = EmbeddedTailnet.peer(named: name, in: peers), peer.online != false,
                  let address = EmbeddedTailnet.address(of: peer), !targets.contains(address) else { continue }
            if let last = warmedAt[address], now - last < .seconds(30) { continue }
            warmedAt[address] = now
            targets.append(address)
        }
        guard !targets.isEmpty, let loopback = try? await node.loopback() else { return }
        ConnectTrace.mark("warm-up: pinging \(targets.count) Mac(s)")
        await withTaskGroup(of: Void.self) { group in
            for address in targets { group.addTask { await Self.ping(address, via: loopback) } }
        }
    }

    /// A disco ping finds the direct path; a TSMP ping goes through WireGuard and sets up its session.
    nonisolated private static func ping(_ address: String, via loopback: TailscaleNode.LoopbackConfig) async {
        for type in ["disco", "TSMP"] {
            var components = URLComponents()
            components.scheme = "http"
            components.host = loopback.ip
            components.port = loopback.port
            components.path = "/localapi/v0/ping"
            components.queryItems = [URLQueryItem(name: "ip", value: address), URLQueryItem(name: "type", value: type)]
            guard let url = components.url else { return }
            var request = URLRequest(url: url, timeoutInterval: 5)
            request.httpMethod = "POST"
            request.setValue("Basic " + Data("tsnet:\(loopback.localAPIKey)".utf8).base64EncodedString(),
                             forHTTPHeaderField: "Authorization")
            request.setValue("localapi", forHTTPHeaderField: "Sec-Tailscale")
            let start = ContinuousClock.now
            let response = try? await URLSession.shared.data(for: request)
            let ok = (response?.1 as? HTTPURLResponse)?.statusCode == 200
            ConnectTrace.mark("warm-up: \(type) ping \(ok ? "ok" : "failed") in \(ContinuousClock.now - start)")
            if !ok { return }
        }
    }

    /// The Mac's status from the peer list as it stands (observable, so the hosts screen follows
    /// the node starting up): checking until the list has arrived.
    func reachability(of hostname: String) -> ReachabilityState {
        guard isEnabled else { return .offline }
        switch state {
        case .starting: return .checking
        case .running where !hasPeerList: return .checking
        case .running:
            guard let peer = EmbeddedTailnet.peer(named: hostname, in: peers),
                  EmbeddedTailnet.address(of: peer) != nil else { return .offline }
            return peer.online == false ? .offline : .online
        case .off, .needsLogin, .failed: return .offline
        }
    }

    /// Opens a TCP connection to `address` through the node, for `VNCConnection.socketProvider`.
    func socketProvider(address: String, port: UInt16, name: String) -> VNCSocketProvider? {
        guard let handle else { return nil }
        let target = address.contains(":") ? "[\(address)]:\(port)" : "\(address):\(port)"
        return {
            var fd: TailscaleConnection = 0
            guard tailscale_dial(handle, "tcp", target, &fd) == 0, fd >= 0 else { throw Problem.unreachable(name) }
            return fd
        }
    }
}

nonisolated extension EmbeddedTailscale.Problem: LocalizedError {
    var errorDescription: String? { message }
}

/// Drops the node's own log lines: they can include addresses and machine names.
private nonisolated struct QuietSink: LogSink {
    var logFileHandle: Int32? { nil }
    func log(_ message: String) {}
}
