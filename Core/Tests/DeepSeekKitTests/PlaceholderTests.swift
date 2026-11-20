import XCTest
@testable import DeepSeekKit

final class PlaceholderTests: XCTestCase {
    func testVersion() { XCTAssertEqual(DeepSeekKitVersion.current, "0.1.0") }
}
