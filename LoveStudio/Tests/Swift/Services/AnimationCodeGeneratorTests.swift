import XCTest
@testable import LoveStudio

final class AnimationCodeGeneratorTests: XCTestCase {

    func testAnnotationsPresent() {
        let output = AnimationCodeGenerator.generate(config: SpriteAnimationConfig(), mode: .luaCATS)
        XCTAssertTrue(output.contains("---@class"))
        XCTAssertTrue(output.contains("---@enum AnimationFrameSelectionMode"))
        XCTAssertTrue(output.contains("---@param dt number"))
        XCTAssertTrue(output.contains("---@return nil"))
    }

    func testAnnotationsAbsentWhenDisabled() {
        let output = AnimationCodeGenerator.generate(config: SpriteAnimationConfig(), mode: .none)
        XCTAssertFalse(output.contains("---@"))
    }
}
