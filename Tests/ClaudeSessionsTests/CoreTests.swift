import XCTest
@testable import ClaudeSessions

/// Unit tests for the pure logic that the app's correctness and safety rest on.
/// Mirrors web/test/unit.mjs so both platforms' duplicated logic stays in step.
final class CoreTests: XCTestCase {

    // MARK: - Secret redaction (mirrors redactSecrets in server.js)

    func testRedactsVendorKeys() {
        XCTAssertFalse(Redaction.redact("sk-ant-api03-abcdefghij0123456789klmnop").contains("abcdefghij"))
        XCTAssertTrue(Redaction.redact("token ghp_ABCDEFGHIJKLMNOPQRST0123456789").contains("[REDACTED]"))
        XCTAssertTrue(Redaction.redact("AKIAIOSFODNN7EXAMPLE").contains("[REDACTED]"))
        XCTAssertTrue(Redaction.redact("Authorization: Bearer abcdefghijklmnopqrstuvwx").contains("[REDACTED]"))
    }

    func testRedactsAssignmentValueKeepsKey() {
        let out = Redaction.redact("DB_PASSWORD=hunter2secret")
        XCTAssertTrue(out.hasPrefix("DB_PASSWORD="))
        XCTAssertTrue(out.contains("[REDACTED]"))
        XCTAssertFalse(out.contains("hunter2secret"))
    }

    func testLeavesProseAndCodeUntouched() {
        XCTAssertEqual(Redaction.redact("call the search API with a function"),
                       "call the search API with a function")
        XCTAssertEqual(Redaction.redact("edit src/main.ts and run npm test"),
                       "edit src/main.ts and run npm test")
        XCTAssertEqual(Redaction.redact(""), "")
    }

    // MARK: - Pricing (mirrors PRICING / rateFor in server.js)

    func testPricingPrefixMatchAndPrecedence() {
        XCTAssertEqual(Pricing.pricing(for: "claude-fable-5").input, 10.0)
        // Generic opus catches 4-8; specific 4-1 must win over generic opus.
        XCTAssertEqual(Pricing.pricing(for: "claude-opus-4-8").input, 5.0)
        XCTAssertEqual(Pricing.pricing(for: "claude-opus-4-1-20250805").input, 15.0)
        XCTAssertEqual(Pricing.pricing(for: "claude-haiku-4-5-20251001").input, 1.0)
    }

    func testCostArithmetic() {
        // 1M input @ $5/M + 1M output @ $25/M = $30 exactly.
        let c = Pricing.cost(model: "claude-opus-4-8",
                             input: 1_000_000, output: 1_000_000, cacheRead: 0, cacheWrite: 0)
        XCTAssertEqual(c, 30.0, accuracy: 0.0001)
    }

    // MARK: - Session id validation + resume script safety

    func testSessionIdValidation() {
        XCTAssertTrue(SessionMeta.isValidSessionId("0f6b3c2a-1111-2222-3333-abcdefabcdef"))
        XCTAssertFalse(SessionMeta.isValidSessionId("x; rm -rf ~"))
        XCTAssertFalse(SessionMeta.isValidSessionId("../../etc/passwd"))
        XCTAssertFalse(SessionMeta.isValidSessionId(""))
    }

    func testResumeScriptNeutralizesInjection() {
        var evil = SessionMeta(sessionId: "0f6b3c2a-1111-2222-3333-abcdefabcdef",
                               transcriptPath: "/dev/null", projectKey: "k")
        evil.cwd = #"/tmp/x";touch /tmp/pwned;#"#
        let script = ResumeService.makeResumeScript(session: evil)
        XCTAssertNotNil(script)
        // The dangerous cwd must be single-quoted; nothing executable escapes.
        XCTAssertTrue(script!.contains("cd '"))
        XCTAssertTrue(script!.contains("exec claude --resume '0f6b3c2a-1111-2222-3333-abcdefabcdef'"))

        // A non-UUID id yields no script at all.
        var bad = SessionMeta(sessionId: "x; rm -rf ~", transcriptPath: "/dev/null", projectKey: "k")
        bad.cwd = "/tmp"
        XCTAssertNil(ResumeService.makeResumeScript(session: bad))
    }
}
