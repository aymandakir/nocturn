import Testing
@testable import Nocturn

@Test
func testAppGracePeriod() async throws {
    let app = AudioApp(
        id: 999,
        bundleID: "com.test.stale",
        displayName: "Stale",
        icon: nil,
        lastActiveDate: .now.addingTimeInterval(-4)
    )

    #expect(Date.now.timeIntervalSince(app.lastActiveDate) > 3)
}
