import Testing
import Foundation
@testable import DuoRemote

struct EmbeddedTailscaleTests {
    private typealias Node = EmbeddedTailnetStatus.Node

    private let mini = Node(hostName: "Maeshs-Mac-mini", dnsName: "maeshs-mac-mini.tail1234.ts.net.",
                            addresses: ["100.114.99.86", "fd7a:115c:a1e0::1"], online: true)
    private let studio = Node(hostName: "studio", dnsName: "studio-1.tail1234.ts.net.",
                              addresses: ["fd7a:115c:a1e0::2"], online: false)

    @Test func decodesStatusAndIgnoresUnknownFields() throws {
        let json = #"""
        {"Version":"1.104","BackendState":"Running","AuthURL":"","AllowSingleHosts":true,
         "Self":{"HostName":"duoremote","TailscaleIPs":["100.91.0.5"],"Extra":1},
         "Peer":{"nodekey:abc":{"HostName":"Maeshs-Mac-mini","DNSName":"maeshs-mac-mini.tail1234.ts.net.",
                                "TailscaleIPs":["100.114.99.86"],"Online":true,"OS":"macOS"}}}
        """#
        let status = try JSONDecoder().decode(EmbeddedTailnetStatus.self, from: Data(json.utf8))
        #expect(status.backendState == "Running")
        #expect(status.ownNode?.addresses == ["100.91.0.5"])
        #expect(status.peers?.count == 1)
        #expect(status.peers?.values.first?.online == true)
    }

    @Test func decodesMinimalStatus() throws {
        let status = try JSONDecoder().decode(EmbeddedTailnetStatus.self, from: Data(#"{"BackendState":"NeedsLogin","AuthURL":"https://login.tailscale.com/a/x"}"#.utf8))
        #expect(status.backendState == "NeedsLogin")
        #expect(status.authURL == "https://login.tailscale.com/a/x")
        #expect(status.peers == nil)
    }

    @Test func findsPeerByMagicDNSMachineNameOrAddress() {
        let peers = [studio, mini]
        #expect(EmbeddedTailnet.peer(named: "maeshs-mac-mini", in: peers) == mini)
        #expect(EmbeddedTailnet.peer(named: "Maeshs-Mac-Mini", in: peers) == mini)
        #expect(EmbeddedTailnet.peer(named: "maeshs-mac-mini.tail1234.ts.net", in: peers) == mini)
        #expect(EmbeddedTailnet.peer(named: "maeshs-mac-mini.tail1234.ts.net.", in: peers) == mini)
        #expect(EmbeddedTailnet.peer(named: "100.114.99.86", in: peers) == mini)
        #expect(EmbeddedTailnet.peer(named: "[fd7a:115c:a1e0::2]", in: peers) == studio)
        // MagicDNS name wins over a machine name, and a machine name still works.
        #expect(EmbeddedTailnet.peer(named: "studio-1", in: peers) == studio)
        #expect(EmbeddedTailnet.peer(named: "studio", in: peers) == studio)
    }

    @Test func onlyPeersMatch() {
        let peers = [mini]
        #expect(EmbeddedTailnet.peer(named: "", in: peers) == nil)
        #expect(EmbeddedTailnet.peer(named: "maeshs", in: peers) == nil)
        #expect(EmbeddedTailnet.peer(named: "192.168.1.5", in: peers) == nil)
        #expect(EmbeddedTailnet.peer(named: "100.114.99.87", in: peers) == nil)
        #expect(EmbeddedTailnet.peer(named: "mini.example.com", in: peers) == nil)
    }

    @Test func dialsIPv4FirstAndOnlyTailscaleAddresses() {
        #expect(EmbeddedTailnet.address(of: mini) == "100.114.99.86")
        #expect(EmbeddedTailnet.address(of: studio) == "fd7a:115c:a1e0::2")
        let odd = Node(hostName: "x", dnsName: nil, addresses: ["192.168.1.5"], online: true)
        #expect(EmbeddedTailnet.address(of: odd) == nil)
    }
}
