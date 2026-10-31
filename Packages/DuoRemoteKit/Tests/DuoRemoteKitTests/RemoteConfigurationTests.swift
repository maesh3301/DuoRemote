import Foundation
import Security
import Testing
@testable import DuoRemoteKit

struct RemoteConfigurationTests {
    private let hosted = RemoteConfiguration(
        name: "Remote", keychainService: "test.host.remote", folder: "Remote",
        defaultsSuite: "test.host.remote.\(UUID().uuidString)", tailscaleNodeName: "host-remote"
    )

    @Test func standaloneKeepsEverythingWhereItAlwaysWas() {
        let config = RemoteConfiguration.standalone
        #expect(config.keychainService == AppInfo.bundleID)
        #expect(config.hostsFile == URL.applicationSupportDirectory.appending(path: "hosts.json"))
        #expect(config.tailscaleDirectory.lastPathComponent == "Tailscale")
        #expect(config.tailscaleDirectory.deletingLastPathComponent().standardizedFileURL == URL.applicationSupportDirectory.standardizedFileURL)
        #expect(config.defaults === UserDefaults.standard)
        #expect(config.tailscaleNodeName == "duoremote")
    }

    @Test func aHostKeepsTheKitInItsOwnPlaces() {
        #expect(hosted.hostsFile == URL.applicationSupportDirectory.appending(path: "Remote/hosts.json"))
        #expect(hosted.tailscaleDirectory.path(percentEncoded: false).hasSuffix("/Remote/Tailscale/"))
        #expect(hosted.defaults !== UserDefaults.standard)
    }

    @Test func aHostsSettingsStayOutOfTheAppsOwn() throws {
        let key = "remote.test.\(UUID().uuidString)"
        let suite = try #require(hosted.defaultsSuite)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        hosted.defaults.set(true, forKey: key)
        #expect(hosted.defaults.bool(forKey: key))
        #expect(UserDefaults.standard.object(forKey: key) == nil)
    }

    /// A fresh install wipes the kit's whole Keychain service, so it must never reach another one.
    /// Package tests have no Keychain access; a host app's first open checks the real thing.
    @Test func keychainQueriesStayInsideTheKitsService() {
        let query = KeychainStore(service: "test.host.remote").serviceQuery
        #expect(query[kSecAttrService as String] as? String == "test.host.remote")
    }

    /// Reads the sources, so a new setting or file can't quietly land in the host's own space.
    @Test func everythingTheKitRemembersGoesThroughTheConfiguration() throws {
        let sources = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/DuoRemoteKit")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "RemoteConfiguration.swift" }
        #expect(files.count > 40)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let name = file.lastPathComponent
            #expect(!text.contains("UserDefaults.standard"), "\(name) uses the app's own settings")
            #expect(!text.contains(".applicationSupportDirectory"), "\(name) picks its own folder")
            #expect(text.firstMatch(of: /@AppStorage\("[^"]+"\)/) == nil, "\(name) has a setting without the kit's store")
            #expect(text.firstMatch(of: /= \.standard\b/) == nil, "\(name) defaults to the app's own settings")
        }
    }
}
