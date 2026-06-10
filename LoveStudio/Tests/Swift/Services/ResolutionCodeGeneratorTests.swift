import XCTest
@testable import LoveStudio

final class ResolutionCodeGeneratorTests: XCTestCase {

    func testAnnotationsPresent() {
        let output = ResolutionCodeGenerator.generate(config: ResolutionConfig(), mode: .luaCATS)
        XCTAssertTrue(output.contains("---@class"))
        XCTAssertTrue(output.contains("---@enum ScalingMode"))
        XCTAssertTrue(output.contains("---@enum FilterMode"))
        XCTAssertTrue(output.contains("---@param w number"))
        XCTAssertTrue(output.contains("---@return number w, number h"))
    }

    func testAnnotationsAbsentWhenDisabled() {
        let output = ResolutionCodeGenerator.generate(config: ResolutionConfig(), mode: .none)
        XCTAssertFalse(output.contains("---@"))
    }
}
