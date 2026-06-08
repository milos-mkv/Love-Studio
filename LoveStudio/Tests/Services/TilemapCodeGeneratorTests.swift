import XCTest
@testable import LoveStudio

final class TilemapCodeGeneratorTests: XCTestCase {

    func testAnnotationsPresent() {
        let output = TilemapCodeGenerator.generate(config: TilemapConfig(), mode: .luaCATS)
        XCTAssertTrue(output.contains("---@class M"))
        XCTAssertTrue(output.contains("---@enum TilemapOrigin"))
        XCTAssertTrue(output.contains("---@enum TilePropertyType"))
        XCTAssertTrue(output.contains("---@enum LayerType"))
        XCTAssertTrue(output.contains("---@param col integer"))
        XCTAssertTrue(output.contains("---@return boolean"))
    }

    func testAnnotationsAbsentWhenDisabled() {
        let output = TilemapCodeGenerator.generate(config: TilemapConfig(), mode: .none)
        XCTAssertFalse(output.contains("---@"))
    }
}
