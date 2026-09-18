import XCTest

final class OurGroceriesAppUITests: XCTestCase {
    func testApplicationLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertNotEqual(app.state, .notRunning)
    }
}
