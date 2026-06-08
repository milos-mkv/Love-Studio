import XCTest
@testable import LoveStudio

final class AudioCodeGeneratorTests: XCTestCase {

    func testAnnotationsPresent() {
        let output = AudioCodeGenerator.generate(config: AudioManagerConfig(), mode: .luaCATS)
        XCTAssertTrue(output.contains("---@class"))
        XCTAssertTrue(output.contains("---@enum AudioSourceType"))
        XCTAssertTrue(output.contains("---@enum AudioGroup"))
        XCTAssertTrue(output.contains("---@param name string"))
        XCTAssertTrue(output.contains("---@return love.Source?"))
    }

    func testAnnotationsAbsentWhenDisabled() {
        let output = AudioCodeGenerator.generate(config: AudioManagerConfig(), mode: .none)
        XCTAssertFalse(output.contains("---@"))
    }
}
