import XCTest
@testable import LoveStudio

final class SaveCodeGeneratorTests: XCTestCase {

    func testAnnotationsPresent() {
        let output = SaveCodeGenerator.generate(config: SaveSystemConfig(), mode: .luaCATS)
        XCTAssertTrue(output.contains("---@class"))
        XCTAssertTrue(output.contains("---@field data table"))
        XCTAssertTrue(output.contains("---@enum SaveFieldType"))
        XCTAssertTrue(output.contains("---@return boolean"))
    }

    func testAnnotationsAbsentWhenDisabled() {
        let output = SaveCodeGenerator.generate(config: SaveSystemConfig(), mode: .none)
        XCTAssertFalse(output.contains("---@"))
    }
}
