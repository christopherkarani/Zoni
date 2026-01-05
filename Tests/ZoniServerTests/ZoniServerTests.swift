import Testing
@testable import ZoniServer

@Suite("ZoniServer Tests")
struct ZoniServerTests {
    @Test("TenantContext initialization")
    func testTenantContextInit() {
        let tenant = TenantContext(
            tenantId: "test-tenant",
            tier: .standard
        )

        #expect(tenant.tenantId == "test-tenant")
        #expect(tenant.tier == .standard)
    }

    @Test("TenantConfiguration defaults")
    func testTenantConfigurationDefaults() {
        let config = TenantConfiguration.default

        #expect(config.queriesPerMinute > 0)
        #expect(config.documentsPerDay > 0)
    }

    @Test("TenantTier presets")
    func testTenantTierPresets() {
        let free = TenantConfiguration.forTier(.free)
        let enterprise = TenantConfiguration.forTier(.enterprise)

        #expect(enterprise.queriesPerMinute > free.queriesPerMinute)
    }
}
