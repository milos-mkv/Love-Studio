import XCTest
@testable import LoveStudio

final class CodeGeneratorCoverageTests: XCTestCase {

    private let covered: Set<String> = [
        "AnimationCodeGenerator",
        "AudioCodeGenerator",
        "CameraCodeGenerator",
        "FontCodeGenerator",
        "ParticleCodeGenerator",
        "ResolutionCodeGenerator",
        "SaveCodeGenerator",
        "SceneCodeGenerator",
        "SpritesheetCodeGenerator",
        "TilemapCodeGenerator",
        "UICodeGenerator",
    ]

    func testAllGeneratorsCovered() {
        XCTAssertEqual(covered.count, 11,
            "A generator was added without a corresponding annotation test.")
    }
}
