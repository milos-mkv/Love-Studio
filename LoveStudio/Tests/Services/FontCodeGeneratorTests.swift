import XCTest
@testable import LoveStudio

final class FontCodeGeneratorTests: XCTestCase {

    func testAnnotationsPresent() {
        let output = FontCodeGenerator.generate(config: FontManagerConfig(), mode: .luaCATS)
        XCTAssertTrue(output.contains("---@class"))
        XCTAssertTrue(output.contains("---@enum FontSource"))
        XCTAssertTrue(output.contains("---@param name string"))
        XCTAssertTrue(output.contains("---@return love.Font?"))
    }

    func testAnnotationsAbsentWhenDisabled() {
        let output = FontCodeGenerator.generate(config: FontManagerConfig(), mode: .none)
        XCTAssertFalse(output.contains("---@"))
    }
}
