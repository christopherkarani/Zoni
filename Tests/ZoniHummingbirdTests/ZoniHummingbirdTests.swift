#if HUMMINGBIRD
import Testing
@testable import ZoniServer

@Suite("ZoniHummingbird Tests")
struct ZoniHummingbirdTests {
    @Test("Version check")
    func testVersion() {
        #expect(!ZoniHummingbird.version.isEmpty)
    }
}
#endif
