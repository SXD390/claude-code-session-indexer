import XCTest
@testable import ClaudeSessions

/// Tests for the OPTIONAL, opt-in FTS5 search index. Everything runs in a temp directory with
/// an injected DB path, so the real Application Support index.db is never touched. If FTS5 is
/// somehow unavailable, the index fails to open and the test skips gracefully (on macOS the
/// system SQLite ships with FTS5, so it runs).
final class SearchIndexTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("csi-index-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
    }

    // A valid transcript filename must be a UUID (matches the scanner's expectation).
    private let sessionWidgets = "11111111-1111-1111-1111-111111111111"
    private let sessionSecret  = "22222222-2222-2222-2222-222222222222"

    /// Writes a synthetic .jsonl transcript and returns a Target describing it.
    private func writeTranscript(_ sessionId: String, project: String, lines: [String]) throws -> SearchIndex.Target {
        let url = tmp.appendingPathComponent("\(sessionId).jsonl")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = (attrs[.modificationDate] as? Date) ?? Date()
        return SearchIndex.Target(sessionId: sessionId, projectKey: project,
                                  transcriptPath: url.path, mtime: mtime, size: size)
    }

    /// Builds an index over two synthetic sessions and returns it (or skips if FTS5 is absent).
    private func makeIndex() throws -> SearchIndex {
        let widgets = try writeTranscript(sessionWidgets, project: "widget-project", lines: [
            #"{"type":"user","timestamp":"2026-07-01T10:00:00.000Z","message":{"content":"how do I configure the widget-factory.build pipeline"}}"#,
            #"{"type":"assistant","timestamp":"2026-07-01T10:00:05.000Z","message":{"content":[{"type":"text","text":"Edit the foo-bar.baz config file to set it up."}]}}"#,
        ])
        // Contains a real-looking secret that MUST be redacted before it lands in the index.
        let secret = try writeTranscript(sessionSecret, project: "other", lines: [
            #"{"type":"user","timestamp":"2026-07-02T11:00:00.000Z","message":{"content":"here is my token ghp_ABCDEFGHIJKLMNOPQRST0123456789 please store it"}}"#,
            #"{"type":"assistant","timestamp":"2026-07-02T11:00:05.000Z","message":{"content":[{"type":"text","text":"I will not persist secrets. Let us talk about databases instead."}]}}"#,
        ])

        let dbURL = tmp.appendingPathComponent("index.db")
        guard let index = SearchIndex(dbURL: dbURL) else {
            throw XCTSkip("SQLite FTS5 unavailable — skipping index tests")
        }
        index.ensureIndex(targets: [widgets, secret])
        return index
    }

    /// A term matches exactly the expected session and no other.
    func testTermMatchesExpectedSession() throws {
        let index = try makeIndex()
        let byId = try XCTUnwrap(index.search(query: "widget-factory.build"), "search must not fail")

        XCTAssertNotNil(byId[sessionWidgets], "the widget session matches")
        XCTAssertFalse(byId[sessionWidgets]?.isEmpty ?? true)
        XCTAssertNil(byId[sessionSecret], "the unrelated session does not match")

        // The matched text column drives results — a project-name-only term must NOT match
        // (project is stored UNINDEXED).
        let projOnly = try XCTUnwrap(index.search(query: "widget-project"))
        XCTAssertTrue(projOnly.isEmpty, "MATCH searches conversation text only, not the project column")
    }

    /// A secret in the source text is REDACTED in the returned snippet.
    func testSecretIsRedactedInSnippet() throws {
        let index = try makeIndex()
        let byId = try XCTUnwrap(index.search(query: "token"))

        let hits = try XCTUnwrap(byId[sessionSecret], "the session with the secret matches on a nearby word")
        let snippet = try XCTUnwrap(hits.first?.snippet)
        XCTAssertTrue(snippet.contains("[REDACTED]"), "the secret is redacted in the snippet")
        XCTAssertFalse(snippet.contains("ghp_ABCDEFGHIJKLMNOPQRST"), "the raw token never appears")
    }

    /// A query with code punctuation doesn't crash the MATCH parser and still matches.
    func testPunctuationQueryDoesNotCrashAndMatches() throws {
        let index = try makeIndex()

        // "foo-bar.baz" would be parsed as FTS operators if unquoted; the phrase-quoting fixes it.
        let byId = try XCTUnwrap(index.search(query: "foo-bar.baz"), "punctuated query must not fail")
        let hits = try XCTUnwrap(byId[sessionWidgets], "foo-bar.baz matches the widget session")
        XCTAssertTrue(hits.contains { $0.snippet.contains("foo-bar.baz") }, "snippet shows the matched phrase")

        // Other punctuation-heavy / degenerate queries must also not crash (may simply not match).
        for weird in ["a.b:c-d", "path/to::thing", "\"unbalanced", "()*"] {
            XCTAssertNotNil(index.search(query: weird), "query \(weird) returns a result set, never a crash")
        }
    }

    /// Re-running ensureIndex without changes is a no-op that keeps results stable (incremental).
    func testIncrementalReindexIsStable() throws {
        let index = try makeIndex()
        let first = try XCTUnwrap(index.search(query: "pipeline"))

        // Rebuild the same targets; mtime/size unchanged → nothing re-indexed, results identical.
        let widgets = SearchIndex.Target(
            sessionId: sessionWidgets, projectKey: "widget-project",
            transcriptPath: tmp.appendingPathComponent("\(sessionWidgets).jsonl").path,
            mtime: (try FileManager.default.attributesOfItem(
                atPath: tmp.appendingPathComponent("\(sessionWidgets).jsonl").path)[.modificationDate] as? Date) ?? Date(),
            size: (try FileManager.default.attributesOfItem(
                atPath: tmp.appendingPathComponent("\(sessionWidgets).jsonl").path)[.size] as? NSNumber)?.int64Value ?? 0)
        index.ensureIndex(targets: [widgets])

        let second = try XCTUnwrap(index.search(query: "pipeline"))
        XCTAssertEqual(first[sessionWidgets]?.count, second[sessionWidgets]?.count,
                       "re-indexing unchanged files does not duplicate rows")
    }
}
