import XCTest
@testable import OurGroceriesMenuBar

final class OurGroceriesAppTests: XCTestCase {
    func testBundleIdentifier() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.cjdelros.OurGroceriesMenuBar")
    }
}
