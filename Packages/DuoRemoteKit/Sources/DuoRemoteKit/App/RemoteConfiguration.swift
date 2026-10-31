import Foundation
import SwiftUI

/// Where the kit keeps what it remembers, and what it calls itself. A host app gives the kit places
/// of its own, so the kit can't read or change the host's Keychain items, files or settings.
public nonisolated struct RemoteConfiguration: Sendable, Equatable {
    /// What the kit calls itself on screen. Nil uses the app's display name.
    public var name: String?
    public var keychainService: String
    /// A folder under Application Support for saved Macs and Tailscale's state. Nil uses it directly.
    public var folder: String?
    /// A settings file of the kit's own. Nil uses the app's standard one.
    public var defaultsSuite: String?
    /// How this device shows up in the tailnet.
    public var tailscaleNodeName: String

    public init(name: String?, keychainService: String, folder: String?, defaultsSuite: String?, tailscaleNodeName: String) {
        self.name = name
        self.keychainService = keychainService
        self.folder = folder
        self.defaultsSuite = defaultsSuite
        self.tailscaleNodeName = tailscaleNodeName
    }

    /// An app that is only DuoRemote.
    public static let standalone = RemoteConfiguration(
        name: nil, keychainService: AppInfo.bundleID, folder: nil, defaultsSuite: nil, tailscaleNodeName: "duoremote"
    )

    var storageDirectory: URL {
        folder.map { URL.applicationSupportDirectory.appending(path: $0, directoryHint: .isDirectory) } ?? .applicationSupportDirectory
    }
    var hostsFile: URL { storageDirectory.appending(path: "hosts.json") }
    var tailscaleDirectory: URL { storageDirectory.appending(path: "Tailscale", directoryHint: .isDirectory) }
    var defaults: UserDefaults { defaultsSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    /// The one in use. Set when the coordinator is made, before anything reads it.
    nonisolated(unsafe) static var current = standalone {
        didSet { UserDefaults.remote = current.defaults }
    }
}

extension UserDefaults {
    /// The kit's settings. Everything the kit remembers in UserDefaults goes through this.
    nonisolated(unsafe) static var remote: UserDefaults = .standard
}

/// How to leave Remote without ending the session, when it runs inside another app.
public struct RemoteExit {
    public var title: String
    public var action: @MainActor () -> Void

    public init(title: String, action: @escaping @MainActor () -> Void) {
        self.title = title
        self.action = action
    }
}

extension EnvironmentValues {
    @Entry var remoteExit: RemoteExit?
}
