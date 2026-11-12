#if canImport(XCTest)
import XCTest
#else
import Foundation
#endif
@testable import StoryBatchCore

extension StoryBatchCoreTests {
    func testAspectSizingAndPixelCaps() throws {
        let a = try CompiledMetaPrompt.compile("aspect=9:7\nPortrait").parameters
        let b = try CompiledMetaPrompt.compile("aspect=18:14\nPortrait").parameters
        XCTAssertEqual(a.width, 1152); XCTAssertEqual(a.height, 896)
        XCTAssertEqual(a.width, b.width); XCTAssertEqual(a.height, b.height)
        XCTAssertEqual(a.aspect, "9:7"); XCTAssertEqual(b.aspect, "9:7")
        XCTAssertEqual(a.pixelMax, 1_048_576)
        let exact = try CompiledMetaPrompt.compile("resolution=1152*896\nPortrait").parameters
        XCTAssertEqual(exact.width, a.width); XCTAssertEqual(exact.height, a.height)
        XCTAssertNil(exact.aspect)
        let wide = try CompiledMetaPrompt.compile("aspect=16:9\nPortrait").parameters
        XCTAssertEqual(wide.width, 1024); XCTAssertEqual(wide.height, 576)
        let tall = try CompiledMetaPrompt.compile("aspect=2:3\nPortrait").parameters
        XCTAssertEqual(tall.width, 768); XCTAssertEqual(tall.height, 1152)
        let square = try CompiledMetaPrompt.compile("aspect=1:1; pixel_max=(1024*1024)-1\nPortrait").parameters
        XCTAssertEqual(square.width, 960); XCTAssertEqual(square.height, 960)
        let expanded = try CompiledMetaPrompt.compile("aspect=18:14; pixel_max=(2048*2048)\nPortrait").parameters
        XCTAssertEqual(expanded.width, 2304); XCTAssertEqual(expanded.height, 1792)
        let boundary = try CompiledMetaPrompt.compile("aspect=9:7; pixel_max=1152*896\nPortrait").parameters
        XCTAssertEqual(boundary.width, 1152); XCTAssertEqual(boundary.height, 896)
        let below = try CompiledMetaPrompt.compile("aspect=9:7; pixel_max=(1152*896)-1\nPortrait").parameters
        XCTAssertEqual(below.width, 576); XCTAssertEqual(below.height, 448)
        for header in ["aspect=9:7; resolution=1152*896", "resolution=1536*1024", "resolution=1152*896; pixel_max=1032191", "pixel_max=262144", "aspect=16:9; pixel_max=4096", "aspect=0:1", "aspect=-1:2", "aspect=1.5:1", "aspect=1:2:3", "aspect=99999999999999999999999:1", "aspect=65536:1; pixel_max=9223372036854775807", "pixel_max=0", "pixel_max=-1", "pixel_max=1.5", "pixel_max=1,2", "pixel_max=1/0", "pixel_max=1e50", "pixel_max=(1024*1024"] {
            XCTAssertThrowsError(try CompiledMetaPrompt.compile(header + "\nPortrait"), header)
        }
        let explicit = try CompiledMetaPrompt.compile("resolution=1536*1024; pixel_max=1536*1024\nPortrait").parameters
        XCTAssertEqual(explicit.width * explicit.height, explicit.pixelMax)
        let largest = try CompiledMetaPrompt.compile("aspect=9223372036854775807:9223372036854775807; pixel_max=9223372036854775807\nPortrait").parameters
        XCTAssertEqual(largest.width, 64 * Int(UInt16.max)); XCTAssertEqual(largest.height, largest.width)
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(explicit)) as! [String: Any]
        old.removeValue(forKey: "pixelMax"); old.removeValue(forKey: "aspect")
        let decoded = try JSONDecoder().decode(BatchParameters.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(decoded.pixelMax); XCTAssertNil(decoded.aspect)
        XCTAssertEqual(decoded.width, explicit.width)
    }

    func testAspectSizingMatchesExhaustiveGrid() throws {
        // Independent enumeration verifies exact ratio, grid alignment and maximal area.
        for a in 1...12 {
            for b in 1...12 {
                for budget in [4096, 262144, 1048576, 2097152] {
                    var expectedWidth = 0, expectedHeight = 0, bestArea = 0
                    for width in stride(from: 64, through: budget / 64, by: 64) {
                        guard width * b % a == 0 else { continue }
                        let height = width * b / a
                        let area = width * height
                        if height > 0, height % 64 == 0, area <= budget, area > bestArea {
                            expectedWidth = width; expectedHeight = height; bestArea = area
                        }
                    }
                    if bestArea == 0 { XCTAssertThrowsError(try AspectSizing.resolve("\(a):\(b)", pixelMax: budget)) }
                    else {
                        let actual = try AspectSizing.resolve("\(a):\(b)", pixelMax: budget)
                        XCTAssertEqual(actual.width, expectedWidth); XCTAssertEqual(actual.height, expectedHeight)
                    }
                }
            }
        }
    }
}
