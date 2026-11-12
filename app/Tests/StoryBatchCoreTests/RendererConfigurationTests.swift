import Foundation
#if canImport(XCTest)
import XCTest
#endif
@testable import StoryBatchCore

extension StoryBatchCoreTests {
    func testRendererConfigurationAndFrozenRecipes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("renderer-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cli = try fakeCLI(in: dir)
        let store = RendererConfigurationStore(url: dir.appendingPathComponent("renderer.local.json"))
        XCTAssertNil(try store.load())
        let recipe = RenderRecipe(model: "test-imported-model.ckpt", sampler: 4, seedMode: 1, guidanceScale: 2.5, resolutionDependentShift: true, loras: [DrawThingsLoRA(file: "test-imported-adapter.ckpt", weight: 0.4, version: "flux1")])
        let config = RendererConfiguration(executablePath: cli.path, recipe: recipe)
        try store.save(config); XCTAssertEqual(try store.load(), config)
        let prepared = try PreparedBatch.prepare("title=renderer; seed=23; count=6; resolution=64*64\nA synthetic test apple.").usingRenderer(recipe).freezingPlans()
        XCTAssertTrue(prepared.frozenPlans!.allSatisfy { $0.recipe == recipe })
        let report = try BatchRunner().run(prepared: prepared, outputRoot: dir, executable: cli) { _ in }
        XCTAssertEqual(report.model, recipe.model)
        XCTAssertEqual(try BatchReport.load(in: URL(fileURLWithPath: report.folder)).model, recipe.model)
        let source = report.images[0]
        XCTAssertTrue(source.command?.contains(recipe.model) == true)
        let json = try JSONSerialization.jsonObject(with: Data(source.plan.configurationJSON().utf8)) as! [String: Any]
        XCTAssertEqual(json["sampler"] as? Int, 4)
        XCTAssertEqual(json["guidanceScale"] as? Double, 2.5)
        let loras = json["loras"] as? [[String: Any]]
        XCTAssertEqual(loras?.first?["file"] as? String, "test-imported-adapter.ckpt")
        XCTAssertEqual(loras?.first?["weight"] as? Double, 0.4)
        XCTAssertEqual(loras?.first?["version"] as? String, "flux1")
        let variant = try PreparedBatch.refinement(of: source.plan, steps: 6, continuing: report)
        XCTAssertEqual(variant.preview[0].recipe, recipe)
        let fragment = try prepared.fragment(at: 4, runID: "test-run").rebased(continuing: report)
        XCTAssertEqual(fragment.frozenPlans?.first?.recipe, recipe)
        XCTAssertEqual(try source.plan.renumbered(99, title: "copy").recipe, recipe)
        let favorites = FavoritesFolder(url: dir.appendingPathComponent("_favorites"))
        try favorites.add(record: source, folder: URL(fileURLWithPath: report.folder))
        XCTAssertEqual(try favorites.images().first?.record?.plan.recipe, recipe)
        var bad = recipe; bad.model = ""
        XCTAssertThrowsError(try bad.validate())
        bad = recipe; bad.loras[0].weight = .infinity
        XCTAssertThrowsError(try bad.validate())
        try Data("not valid JSON".utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try String(contentsOf: store.url, encoding: .utf8), "not valid JSON")
        let legacy = ImagePlan(number: 1, seed: 1, shift: try ShiftValue("1.75"), steps: 3, width: 64, height: 64, prompt: "Synthetic fixture", filename: "fixture.png")
        XCTAssertNil(try JSONDecoder().decode(ImagePlan.self, from: JSONEncoder().encode(legacy)).recipe)
        let legacyJSON = try JSONSerialization.jsonObject(with: Data(legacy.configurationJSON().utf8)) as! [String: Any]
        XCTAssertEqual(legacyJSON["model"] as? String, GenerationDefaults.model)
    }
}
