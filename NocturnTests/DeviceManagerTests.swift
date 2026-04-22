import Testing
@testable import Nocturn

@Test
func testDeviceDiscovery() async throws {
    let manager = DeviceManager()
    await manager.refresh()
    #expect(!manager.outputDevices.isEmpty)
    #expect(manager.defaultOutput != nil)
}
