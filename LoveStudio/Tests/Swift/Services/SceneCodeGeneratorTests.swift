import XCTest
@testable import LoveStudio

final class SceneCodeGeneratorTests: XCTestCase {

    func testAnnotationsPresent() {
        let output = SceneCodeGenerator.generateModule(config: SceneManagerConfig(), mode: .luaCATS)
        XCTAssertTrue(output.contains("---@class"))
        XCTAssertTrue(output.contains("---@enum SceneTransitionEffect"))
        XCTAssertTrue(output.contains("---@enum SceneTransitionEasing"))
        XCTAssertTrue(output.contains("---@enum SceneCompleteTrigger"))
        XCTAssertTrue(output.contains("---@enum SceneCompleteAction"))
        XCTAssertTrue(output.contains("---@param name string"))
        XCTAssertTrue(output.contains("---@return table?"))
    }

    func testAnnotationsAbsentWhenDisabled() {
        let output = SceneCodeGenerator.generateModule(config: SceneManagerConfig(), mode: .none)
        XCTAssertFalse(output.contains("---@"))
    }
}
