import Foundation
import Testing
@testable import DuoRemoteKit

struct PackagingTests {
    @Test func acknowledgementsShipWithTheKit() {
        #expect(Bundle.module.url(forResource: "Acknowledgements", withExtension: "txt") != nil)
    }
}
