import Foundation

/// A saved Mac. The password lives in the Keychain, never here.
public struct Host: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var hostname: String          // tailnet name, e.g. "my-mac"
    public var port: UInt16 = 5900
    public var username: String
    /// SF Symbol name; see `HostSymbol`. nil means `desktopcomputer`.
    public var symbol: String?
    public var lastConnected: Date?
    /// Per-Mac scroll speed; nil = use the global default (Settings).
    public var scrollSpeed: Double?
    /// Send the password even when the Mac isn't reached through Tailscale, or asks for a plain
    /// VNC password instead of a macOS sign-in.
    public var allowOutsideTailscale = false
    /// How the Mac is reached: the system's network (the Tailscale app, or a local network) or
    /// DuoRemote's built-in Tailscale.
    public var route: HostRoute = .system

    public init(id: UUID = UUID(), name: String, hostname: String, port: UInt16 = 5900, username: String,
         symbol: String? = nil, lastConnected: Date? = nil) {
        self.id = id
        self.name = name
        self.hostname = hostname
        self.port = port
        self.username = username
        self.symbol = symbol
        self.lastConnected = lastConnected
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        hostname = try c.decode(String.self, forKey: .hostname)
        port = try c.decodeIfPresent(UInt16.self, forKey: .port) ?? 5900
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? ""
        symbol = try c.decodeIfPresent(String.self, forKey: .symbol)
        lastConnected = try c.decodeIfPresent(Date.self, forKey: .lastConnected)
        scrollSpeed = try c.decodeIfPresent(Double.self, forKey: .scrollSpeed)
        allowOutsideTailscale = try c.decodeIfPresent(Bool.self, forKey: .allowOutsideTailscale) ?? false
        route = (try? c.decodeIfPresent(HostRoute.self, forKey: .route)) ?? .system
    }

    public var symbolName: String { symbol ?? HostSymbol.defaultName }
}

public enum HostRoute: String, Codable, CaseIterable, Sendable {
    case system
    case embeddedTailscale
}

/// The Mac icons offered in the editor.
public enum HostSymbol {
    public static let defaultName = "desktopcomputer"
    public static let all = ["macmini", "laptopcomputer", "desktopcomputer", "macstudio", "display"]

    public static func label(_ name: String) -> String {
        switch name {
        case "macmini": "Mac mini"
        case "laptopcomputer": "MacBook"
        case "macstudio": "Mac Studio"
        case "display": "iMac or display"
        default: "Desktop Mac"
        }
    }
}
