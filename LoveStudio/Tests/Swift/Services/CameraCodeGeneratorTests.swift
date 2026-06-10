import XCTest
@testable import LoveStudio

final class CameraCodeGeneratorTests: XCTestCase {

    func testAnnotationsPresent() {
        let output = CameraCodeGenerator.generate(config: CameraConfig(), mode: .luaCATS)
        XCTAssertTrue(output.contains("---@class Camera"))
        XCTAssertTrue(output.contains("---@field x number"))
        XCTAssertTrue(output.contains("---@param x number?"))
        XCTAssertTrue(output.contains("---@return Camera"))
    }

    func testAnnotationsAbsentWhenDisabled() {
        let output = CameraCodeGenerator.generate(config: CameraConfig(), mode: .none)
        XCTAssertFalse(output.contains("---@"))
    }
}
