// Minimal assertion runner for Macs with Command Line Tools but no XCTest.
// The same test cases also run under XCTest when Xcode is installed.
import Foundation
import Darwin

#if !canImport(XCTest)
private let assertionLock = NSLock()
var failures = 0
func XCTFail(_ message: String = "Assertion failed", file: StaticString = #filePath, line: UInt = #line) {
    assertionLock.lock(); failures += 1; assertionLock.unlock()
    print("FAIL \(file):\(line): \(message)")
}
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) rethrows {
    if try !value() { XCTFail("Expected true. " + message, file: file, line: line) }
}
func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) rethrows { if try value() { XCTFail("Expected false", file: file, line: line) } }
func XCTAssertEqual<T: Equatable>(_ left: T, _ right: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    if left != right { XCTFail("\(left) != \(right). " + message, file: file, line: line) }
}
func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double, file: StaticString = #filePath, line: UInt = #line) { if abs(a-b) > accuracy { XCTFail("\(a) differs from \(b)", file: file, line: line) } }
func XCTAssertNotNil<T>(_ a: T?, file: StaticString = #filePath, line: UInt = #line) { if a == nil { XCTFail("Expected value", file: file, line: line) } }
func XCTAssertNil<T>(_ a: T?, file: StaticString = #filePath, line: UInt = #line) { if a != nil { XCTFail("Expected nil", file: file, line: line) } }
func XCTAssertGreaterThan<T: Comparable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { if a <= b { XCTFail("Expected \(a) > \(b)", file: file, line: line) } }
func XCTAssertLessThanOrEqual<T: Comparable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { if a > b { XCTFail("Expected \(a) <= \(b)", file: file, line: line) } }
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try value(); XCTFail("Expected error. " + message, file: file, line: line) } catch {}
}
final class TestExpectation {
    let semaphore = DispatchSemaphore(value: 0)
    func fulfill() { semaphore.signal() }
}
class XCTestCase {
    func expectation(description: String) -> TestExpectation { TestExpectation() }
    func wait(for expectations: [TestExpectation], timeout: Double) {
        for e in expectations { if e.semaphore.wait(timeout: .now() + timeout) == .timedOut { XCTFail("Timed out after \(timeout) seconds") } }
    }
}
#endif

#if !STORYBATCH_MODEL_TESTS
@main struct StandaloneTests {
    static func main() {
        let suite = StoryBatchCoreTests()
        let tests: [(String, () throws -> Void)] = [
            ("aspect normalization and pixel caps", suite.testAspectSizingAndPixelCaps),
            ("maximal exact aspect grid sizing", suite.testAspectSizingMatchesExhaustiveGrid),
            ("shared fresh and nested fields", suite.testSharedFreshFieldsAndNestedResolution),
            ("field preflight multiline and safety bounds", suite.testFieldPreflightAndMultilineValues),
            ("choice extraction and field batch identity", suite.testExtractionAndFieldBatchIdentity),
            ("field queue continuation and image recipe snapshots", suite.testFieldContinuationFrozenQueueAndRecipeSnapshots),
            ("defaults and header", suite.testDefaultsAndHeader),
            ("local renderer config and frozen model/LoRA recipes", suite.testRendererConfigurationAndFrozenRecipes),
            ("fixed parameters and precision", suite.testFixedParametersAndDecimalPrecision),
            ("random seed and shift ranges", suite.testRandomSeedsAndThousandthShifts),
            ("ordered shift lists and continuation", suite.testOrderedShiftListsValidationAndContinuation),
            ("paired seed lists and random placeholders", suite.testSeedListsPairWithShiftListsAndRandomPlaceholders),
            ("seed random remainder expansion and validation", suite.testSeedRandomRemainder),
            ("mixed shift ranges and remainder", suite.testMixedShiftRangesAndRemainder),
            ("render retry recovery and one-retry limit", suite.testRenderRetriesOnceWithFrozenRecipe),
            ("frozen queue cancellation and pairing", suite.testFrozenQueueCancellationPreservesPairingAndNumbering),
            ("skip current image before launch and continue", suite.testSkipCurrentImageBeforeLaunchPreservesRemainder),
            ("queue fragments retain recipes and accounting", suite.testQueueFragmentsKeepInputsAccountingAndCanceledAttempts),
            ("shift arithmetic scalars lists and ranges", suite.testShiftArithmeticInScalarsListsAndRanges),
            ("wrapped shift operations and collected parameters", suite.testWrappedShiftOperationsAndCollectedParameters),
            ("constrained shift range", suite.testConstrainedShiftRange),
            ("nested weighted distribution", suite.testWeightsNestedBranchesAndDuplicates),
            ("empty and lazy nested terms", suite.testEmptySingleAndLazyNestedTerms),
            ("malformed branch preflight", suite.testMalformedBranchesFailBeforeGeneration),
            ("safe Unicode filenames", suite.testSafeFilenamesAndUnicodeLength),
            ("sequential runner and reports", suite.testPreviewIsExactlyUsedAndReportsWrittenPerImage),
            ("cancellation removes empty batch", suite.testCancellationStopsCurrentImageAndDoesNotStartNext),
            ("generate more appends safely", suite.testGenerateMoreAppendsWithoutOverwritingAndKeepsImplicitTitle),
            ("parameter-only continuation and history", suite.testParameterOnlyEditsContinueWithNewSettingsAndPreserveHistory),
            ("canceled more retains earlier outputs", suite.testCanceledMorePreservesExistingImagesAndSkipsAttemptedNumber),
            ("draft persistence and running snapshot", suite.testDraftPersistenceAndRunningRecipeSnapshot),
            ("refinement buttons and exact recipe", suite.testRefinementStepButtonsAndExactRecipe),
            ("shift bump precision and exact recipe", suite.testShiftBumpsPreservePrecisionAndOnlyChangeShift),
            ("refinements after current round", suite.testRefinementsFollowAllImagesInCurrentRoundInOrder)
        ]
        for (name, test) in tests {
            do { try test(); print("Checked: \(name)") }
            catch { XCTFail("\(name): \(error)") }
        }
        #if !canImport(XCTest)
        print("\(tests.count) test groups, \(failures) failures")
        exit(failures == 0 ? 0 : 1)
        #endif
    }
}
#endif
