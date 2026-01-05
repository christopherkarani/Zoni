import Testing
@testable import ZoniVapor

@Suite("ZoniVapor Tests")
struct ZoniVaporTests {
    @Test("Version check")
    func testVersion() {
        #expect(!ZoniVapor.version.isEmpty)
    }
}
