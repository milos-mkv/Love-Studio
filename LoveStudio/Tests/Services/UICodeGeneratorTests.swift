import XCTest
@testable import LoveStudio

final class UICodeGeneratorTests: XCTestCase {

    func testAnnotationsPresent() {
        let output = UICodeGenerator.generate(config: UIBuilderConfig(), mode: .luaCATS)
        XCTAssertTrue(output.contains("---@class"))
        XCTAssertTrue(output.contains("---@enum UIElementType"))
        XCTAssertTrue(output.contains("---@param dt number"))
        XCTAssertTrue(output.contains("---@return nil"))
    }

    func testAnnotationsAbsentWhenDisabled() {
        let output = UICodeGenerator.generate(config: UIBuilderConfig(), mode: .none)
        XCTAssertFalse(output.contains("---@"))
    }
}
