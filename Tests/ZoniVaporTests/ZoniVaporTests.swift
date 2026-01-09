#if VAPOR
import Testing
@testable import ZoniServer
#if canImport(ZoniVapor)
// If ZoniVapor was a separate module, we wouldn't import it here if merged.
// But since we merged, we import ZoniServer.
#endif

@Suite("ZoniVapor Tests")
struct ZoniVaporTests {
    @Test("Version check")
    func testVersion() {
        // Assuming ZoniVapor enum/struct exists in ZoniServer
        #expect(!ZoniVapor.version.isEmpty)
    }
}
#endif
