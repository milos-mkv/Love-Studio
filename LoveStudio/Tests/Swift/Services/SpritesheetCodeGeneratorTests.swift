import XCTest
@testable import LoveStudio

final class SpritesheetCodeGeneratorTests: XCTestCase {

    private let emptyPackResult = PackResult(
        packed: [],
        atlasSize: CGSize(width: 256, height: 256),
        atlasImage: nil,
        failed: []
    )

    func testAnnotationsPresent() {
        let output = SpritesheetCodeGenerator.generate(config: SpritesheetConfig(), packResult: emptyPackResult, mode: .luaCATS)
        XCTAssertTrue(output.contains("---@class"))
        XCTAssertTrue(output.contains("---@param name string"))
        XCTAssertTrue(output.contains("---@return love.Quad?"))
        XCTAssertTrue(output.contains("---@return love.Image?"))
        XCTAssertTrue(output.contains("---@return number w, number h"))
    }

    func testAnnotationsAbsentWhenDisabled() {
        let output = SpritesheetCodeGenerator.generate(config: SpritesheetConfig(), packResult: emptyPackResult, mode: .none)
        XCTAssertFalse(output.contains("---@"))
    }
}
