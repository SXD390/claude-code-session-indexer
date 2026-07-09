import Foundation
import SQLite3

/// SQLite requires this sentinel destructor so bound text is COPIED into the statement
/// (our Swift strings are transient). `SQLITE_TRANSIENT` isn't imported from the C headers.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// OPTIONAL, OPT-IN full-text-search backend over the system SQLite (libsqlite3, which ships
/// with macOS and includes FTS5). Import is `import SQLite3`; the library is linked via
/// `linkerSettings: [.linkedLibrary("sqlite3")]` in Package.swift — NO SwiftPM dependency.
///
/// Off by default: nothing here runs, and no DB is created, unless `isEnabled` is true.
/// When enabled, deep search prefers this index; on ANY failure the caller falls back to the
/// existing concurrent linear scan, so behavior stays correct and invisible to the UI.
///
/// The index stores REDACTED text (via `TranscriptScanner.extractIndexRows`, which reuses
/// `Redaction.redact`), so search snippets are redacted just like the scan path's.
final class SearchIndex {

    /// Opt-in switch: env `CSI_INDEX=1` OR the persisted UserDefaults toggle.
    static var isEnabled: Bool {
        if ProcessInfo.processInfo.environment["CSI_INDEX"] == "1" { return true }
        return UserDefaults.standard.bool(forKey: "csiSearchIndexEnabled")
    }

    /// Default on-disk location, alongside the JSON caches. Accessing this creates the
    /// Application Support/ClaudeSessions directory as a side effect (like the other caches).
    static var dbURL: URL {
        SessionStore.appSupportDir.appendingPathComponent("index.db")
    }

    /// A Sendable snapshot of the fields the indexer needs, so it can run off the main actor.
    struct Target: Sendable {
        let sessionId: String
        let projectKey: String
        let transcriptPath: String
        let mtime: Date
        let size: Int64
    }

    private var db: OpaquePointer?

    /// Opens (creating if needed) the DB and ensures the schema exists. Returns nil on ANY
    /// failure so the caller falls back to the scan. `dbURL` is injectable for tests.
    init?(dbURL: URL = SearchIndex.dbURL) {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(dbURL.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            return nil
        }
        self.db = handle
        guard createSchema() else {
            sqlite3_close(handle)
            self.db = nil
            return nil
        }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Schema

    private func createSchema() -> Bool {
        // Only `text` is indexed; the rest are UNINDEXED so a MATCH searches conversation text
        // only (never a project name / role / timestamp) — matching the scan's semantics.
        let fts = """
        CREATE VIRTUAL TABLE IF NOT EXISTS messages USING fts5(
            session_id UNINDEXED, project UNINDEXED, role UNINDEXED, text, ts UNINDEXED
        );
        """
        // Per-transcript tracking so re-indexing is incremental (mtime/size, like the meta cache).
        let files = "CREATE TABLE IF NOT EXISTS files(path TEXT PRIMARY KEY, mtime REAL, size INTEGER);"
        return exec(fts) && exec(files)
    }

    // MARK: - Incremental indexing

    /// (Re)indexes only transcripts whose mtime/size changed since last time. For a changed
    /// session, its old rows are deleted and the redacted messages re-inserted. Best-effort:
    /// any single-statement failure is skipped; the search path still falls back on read errors.
    func ensureIndex(targets: [Target]) {
        guard db != nil else { return }

        var known: [String: (mtime: Double, size: Int64)] = [:]
        if let stmt = prepare("SELECT path, mtime, size FROM files;") {
            while sqlite3_step(stmt) == SQLITE_ROW {
                let path = columnText(stmt, 0)
                known[path] = (sqlite3_column_double(stmt, 1), sqlite3_column_int64(stmt, 2))
            }
            sqlite3_finalize(stmt)
        }

        let changed = targets.filter { t in
            guard let k = known[t.transcriptPath] else { return true }
            return k.size != t.size || abs(k.mtime - t.mtime.timeIntervalSince1970) > 0.0005
        }
        guard !changed.isEmpty else { return }

        _ = exec("BEGIN;")
        for t in changed { reindexOne(t) }
        _ = exec("COMMIT;")
    }

    private func reindexOne(_ t: Target) {
        if let del = prepare("DELETE FROM messages WHERE session_id = ?;") {
            bindText(del, 1, t.sessionId)
            _ = sqlite3_step(del)
            sqlite3_finalize(del)
        }

        let rows = TranscriptScanner.extractIndexRows(url: URL(fileURLWithPath: t.transcriptPath))
        if let ins = prepare("INSERT INTO messages(session_id, project, role, text, ts) VALUES(?,?,?,?,?);") {
            for r in rows {
                sqlite3_reset(ins)
                sqlite3_clear_bindings(ins)
                bindText(ins, 1, t.sessionId)
                bindText(ins, 2, t.projectKey)
                bindText(ins, 3, r.role)
                bindText(ins, 4, r.text)
                bindText(ins, 5, r.timestamp.map { String($0.timeIntervalSince1970) } ?? "")
                _ = sqlite3_step(ins)
            }
            sqlite3_finalize(ins)
        }

        if let f = prepare("INSERT OR REPLACE INTO files(path, mtime, size) VALUES(?,?,?);") {
            bindText(f, 1, t.transcriptPath)
            sqlite3_bind_double(f, 2, t.mtime.timeIntervalSince1970)
            sqlite3_bind_int64(f, 3, t.size)
            _ = sqlite3_step(f)
            sqlite3_finalize(f)
        }
    }

    // MARK: - Search

    /// FTS5 MATCH over the redacted `text` column. Returns per-session redacted ±120-char
    /// snippets (same shape as the scan's `RawDeepMatch`), keyed by session id. Returns nil on
    /// ANY SQLite error so the caller falls back to the scan; returns [:] for too-short queries.
    func search(query: String, rowLimit: Int = 5000, perSessionCap: Int = 8) -> [String: [RawDeepMatch]]? {
        guard db != nil else { return nil }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3 else { return [:] }

        guard let stmt = prepare(
            "SELECT session_id, role, text, ts FROM messages WHERE messages MATCH ? ORDER BY rank LIMIT ?;"
        ) else { return nil }
        defer { sqlite3_finalize(stmt) }

        bindText(stmt, 1, matchExpression(for: q))
        sqlite3_bind_int(stmt, 2, Int32(clamping: rowLimit))

        var byId: [String: [RawDeepMatch]] = [:]
        var rc = sqlite3_step(stmt)
        while rc == SQLITE_ROW {
            let sid = columnText(stmt, 0)
            if (byId[sid]?.count ?? 0) < perSessionCap {
                let role = columnText(stmt, 1)
                let text = columnText(stmt, 2)
                let ts = Double(columnText(stmt, 3)).map { Date(timeIntervalSince1970: $0) }
                let snip = TranscriptScanner.makeSnippet(text: text, query: q)
                byId[sid, default: []].append(RawDeepMatch(role: role, snippet: snip, timestamp: ts))
            }
            rc = sqlite3_step(stmt)
        }
        // A MATCH-syntax error (or any I/O error) surfaces here → fall back to the scan.
        guard rc == SQLITE_DONE else { return nil }
        return byId
    }

    /// Wraps the whole query as a single FTS5 phrase, doubling any embedded quotes. This keeps
    /// code punctuation (hyphens/dots/colons) from being parsed as FTS operators — they simply
    /// tokenize inside the phrase — so `foo-bar.baz` matches instead of erroring.
    private func matchExpression(for query: String) -> String {
        "\"" + query.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - C-API helpers

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        return stmt
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: c)
    }
}
