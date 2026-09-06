import XCTest
@testable import AmpMac

final class SuiteTests: XCTestCase {
    @MainActor private func runSuite(_ name: String) {
        let results = TestKit.run(filter: name + "/")
        XCTAssertFalse(results.isEmpty)
        for r in results { for f in r.failures { XCTFail("\(r.suite)/\(r.name): \(f)") } }
    }
    @MainActor func testDSP() { runSuite("DSP") }
    @MainActor func testChain() { runSuite("Chain") }
    @MainActor func testPresets() { runSuite("Presets") }
    @MainActor func testDevices() { runSuite("Devices") }
    @MainActor func testLevel() { runSuite("Level") }
    @MainActor func testChordmap() { runSuite("Chordmap") }
    @MainActor func testCLI() { runSuite("CLI") }
}
