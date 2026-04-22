import Testing
@testable import Nocturn

@Test
func testVolumeMapping() {
    let app = AudioApp(
        id: 1234,
        bundleID: "com.test.app",
        displayName: "Test",
        icon: nil
    )
    app.volume = 0.72
    #expect(app.volume == 0.72)

    app.isBoostEnabled = true
    app.volume = 1.5
    #expect(app.volume <= 1.5)
}
