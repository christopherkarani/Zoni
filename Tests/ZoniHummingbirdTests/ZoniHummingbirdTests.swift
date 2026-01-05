import Testing
@testable import ZoniHummingbird

@Suite("ZoniHummingbird Tests")
struct ZoniHummingbirdTests {
    @Test("Version check")
    func testVersion() {
        #expect(!ZoniHummingbird.version.isEmpty)
    }
}
