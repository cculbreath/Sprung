import XCTest
import OrderedCollections
@testable import Sprung

/// Pins the canonical truthiness contract for template-context visibility.
///
/// Before consolidation there were two diverging `truthy(_:)` copies:
/// `ResumeTemplateDataBuilder` treated whitespace-only strings as present
/// (`"   "` → field shown) while `HandlebarsContextAugmentor` trimmed them away
/// (`"   "` → field hidden). The same value rendered differently depending on
/// the engine. These tests encode the unified, correct contract: whitespace-only
/// strings and empty containers are absent.
final class JSONContextCoercionTests: XCTestCase {

    func testEmptyAndWhitespaceOnlyStringsAreFalsy() {
        XCTAssertFalse(JSONContextCoercion.truthy(""))
        XCTAssertFalse(JSONContextCoercion.truthy("   "))
        XCTAssertFalse(JSONContextCoercion.truthy("\n\t  "))
    }

    func testNonEmptyStringsAreTruthy() {
        XCTAssertTrue(JSONContextCoercion.truthy("x"))
        XCTAssertTrue(JSONContextCoercion.truthy("  padded  "))
    }

    func testNilIsFalsy() {
        XCTAssertFalse(JSONContextCoercion.truthy(nil))
    }

    func testArraysFollowEmptiness() {
        XCTAssertFalse(JSONContextCoercion.truthy([Any]()))
        XCTAssertTrue(JSONContextCoercion.truthy([1, 2, 3]))
    }

    func testDictionariesFollowEmptiness() {
        XCTAssertFalse(JSONContextCoercion.truthy([String: Any]()))
        XCTAssertTrue(JSONContextCoercion.truthy(["a": 1]))
    }

    func testOrderedDictionariesFollowEmptiness() {
        XCTAssertFalse(JSONContextCoercion.truthy(OrderedDictionary<String, Any>()))
        var ordered = OrderedDictionary<String, Any>()
        ordered["a"] = 1
        XCTAssertTrue(JSONContextCoercion.truthy(ordered))
    }

    func testNumbersUseBoolValue() {
        XCTAssertTrue(JSONContextCoercion.truthy(NSNumber(value: true)))
        XCTAssertFalse(JSONContextCoercion.truthy(NSNumber(value: false)))
        XCTAssertTrue(JSONContextCoercion.truthy(NSNumber(value: 1)))
        XCTAssertFalse(JSONContextCoercion.truthy(NSNumber(value: 0)))
    }

    func testUnknownTypesAreTruthy() {
        XCTAssertTrue(JSONContextCoercion.truthy(Date()))
    }
}
