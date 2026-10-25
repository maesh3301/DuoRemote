import Testing
@preconcurrency import RoyalVNCKit
@testable import DuoRemote

struct CredentialPolicyTests {
    @Test func tailscaleIPv4Range() {
        #expect(Tailnet.isTailscaleAddress("100.64.0.1"))
        #expect(Tailnet.isTailscaleAddress("100.101.102.103"))
        #expect(Tailnet.isTailscaleAddress("100.127.255.255"))
        #expect(!Tailnet.isTailscaleAddress("100.63.255.255"))
        #expect(!Tailnet.isTailscaleAddress("100.128.0.1"))
        #expect(!Tailnet.isTailscaleAddress("192.168.1.10"))
        #expect(!Tailnet.isTailscaleAddress("10.0.0.1"))
    }

    @Test func tailscaleIPv6Range() {
        #expect(Tailnet.isTailscaleAddress("fd7a:115c:a1e0::1"))
        #expect(Tailnet.isTailscaleAddress("fd7a:115c:a1e0:ab12:4843:cd96:6258:b240"))
        #expect(!Tailnet.isTailscaleAddress("fd7a:115c:a1e1::1"))
        #expect(!Tailnet.isTailscaleAddress("fe80::1"))
        #expect(!Tailnet.isTailscaleAddress("2001:db8::1"))
        #expect(Tailnet.isTailscaleAddress("::ffff:100.64.1.2"))
        #expect(!Tailnet.isTailscaleAddress("::ffff:192.168.1.2"))
    }

    @Test func namesAndJunkAreNotAddresses() {
        #expect(!Tailnet.isTailscaleAddress("my-mac"))
        #expect(!Tailnet.isTailscaleAddress("my-mac.tail1234.ts.net"))
        #expect(!Tailnet.isTailscaleAddress(""))
        #expect(!Tailnet.isTailscaleAddress("100.64.0"))
    }

    private func path(_ remote: String, _ local: String? = "100.70.0.2", _ interface: String? = "utun4") -> Tailnet.Path {
        Tailnet.Path(remote: remote, local: local, interface: interface)
    }

    @Test func everyPathMustGoThroughTheTunnel() {
        #expect(Tailnet.decide([path("100.80.0.1")]) == .tailnet("100.80.0.1"))
        #expect(Tailnet.decide([path("fd7a:115c:a1e0::5", "fd7a:115c:a1e0::2"), path("100.80.0.1")]) == .tailnet("100.80.0.1"))
        #expect(Tailnet.decide([path("100.80.0.1"), path("192.168.1.5", "192.168.1.9", "en0")]) == .outside("192.168.1.5"))
        #expect(Tailnet.decide([]) == .unresolved)
    }

    @Test func tailscaleAddressRoutedElsewhereIsOutside() {
        // A hostile network answering DNS with 100.x and routing it itself.
        #expect(Tailnet.decide([path("100.80.0.1", "192.168.1.9", "en0")]) == .outside("100.80.0.1"))
        // A carrier's CGNAT address on the cellular interface.
        #expect(Tailnet.decide([path("100.80.0.1", "100.72.3.4", "pdp_ip0")]) == .outside("100.80.0.1"))
        #expect(Tailnet.decide([path("100.80.0.1", nil, nil)]) == .outside("100.80.0.1"))
    }

    @Test func nat64CopiesOfIPv4AnswersAreIgnored() {
        #expect(Tailnet.nat64Embedded("64:ff9b::6450:1") == "100.80.0.1")
        #expect(Tailnet.nat64Embedded("2001:db8::1") == nil)
        let synthesized = path("64:ff9b::6450:1", "2607:fb90::1", "pdp_ip0")
        #expect(Tailnet.decide([path("100.80.0.1"), synthesized]) == .tailnet("100.80.0.1"))
        #expect(Tailnet.decide([synthesized]) == .outside("64:ff9b::6450:1"))
    }

    @Test func passwordGoesOutOnlyOverTailscaleUnlessAllowed() {
        #expect(CredentialPolicy.maySend(over: .tailnet("100.80.0.1"), allowOutsideTailscale: false, approvedAddress: nil))
        #expect(!CredentialPolicy.maySend(over: .outside("192.168.1.5"), allowOutsideTailscale: false, approvedAddress: nil))
        #expect(CredentialPolicy.maySend(over: .outside("192.168.1.5"), allowOutsideTailscale: true, approvedAddress: nil))
        #expect(CredentialPolicy.maySend(over: .outside("192.168.1.5"), allowOutsideTailscale: false, approvedAddress: "192.168.1.5"))
        #expect(!CredentialPolicy.maySend(over: .outside("192.168.1.6"), allowOutsideTailscale: false, approvedAddress: "192.168.1.5"))
        #expect(!CredentialPolicy.maySend(over: .unresolved, allowOutsideTailscale: false, approvedAddress: nil))
        #expect(CredentialPolicy.maySend(over: .unresolved, allowOutsideTailscale: true, approvedAddress: nil))
    }

    @Test func onlyMacOSSignInIsAnsweredByDefault() {
        #expect(CredentialPolicy.mayAnswer(.appleRemoteDesktop, allowOutsideTailscale: false))
        #expect(!CredentialPolicy.mayAnswer(.vnc, allowOutsideTailscale: false))
        #expect(!CredentialPolicy.mayAnswer(.ultraVNCMSLogonII, allowOutsideTailscale: false))
        #expect(CredentialPolicy.mayAnswer(.vnc, allowOutsideTailscale: true))
    }

    @Test func blockedFailuresDontRetry() {
        #expect(!RetryPolicy.shouldRetry(.outsideTailscale))
        #expect(!RetryPolicy.shouldRetry(.insecureAuthentication))
    }
}
