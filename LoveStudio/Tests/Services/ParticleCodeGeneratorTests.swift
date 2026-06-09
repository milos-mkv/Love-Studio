import XCTest
@testable import LoveStudio

final class ParticleCodeGeneratorTests: XCTestCase {

    func testAnnotationsPresent() {
        let output = ParticleCodeGenerator.generate(config: ParticleSystemConfig(), mode: .luaCATS)
        XCTAssertTrue(output.contains("---@class"))
        XCTAssertTrue(output.contains("---@enum ParticleShape"))
        XCTAssertTrue(output.contains("---@enum ParticleEmitterShape"))
        XCTAssertTrue(output.contains("---@enum ParticleBlendMode"))
        XCTAssertTrue(output.contains("---@param dt number"))
        XCTAssertTrue(output.contains("---@return boolean"))
    }

    func testBurstAnnotationPresent() {
        var config = ParticleSystemConfig()
        config.isBurst = true
        let output = ParticleCodeGenerator.generate(config: config, mode: .luaCATS)
        XCTAssertTrue(output.contains("---@param x number?"))
    }

    func testAnnotationsAbsentWhenDisabled() {
        let output = ParticleCodeGenerator.generate(config: ParticleSystemConfig(), mode: .none)
        XCTAssertFalse(output.contains("---@"))
    }
}
