// 選字模型：Python cjlearn/model.py 的逐行移植。行為必須與 Python 版完全一致。
// 注意：Swift 的 String 以「正規等價」比較（相容漢字會等於統一漢字），Python 則逐碼點比較，
// 因此所有以字為 key 的字典都改用 UTF-8 位元組陣列當 key。
import Foundation
import SQLite3

let CTX_LEN = 3                                      // 往前看幾個字
let W_NGRAM: [Int: Double] = [1: 1.5, 2: 2.0, 3: 2.5] // 上文長度 k → 詞內 n-gram 權重
let W_USER_BI = 3.0                                  // 使用者「前一字→此字」次數
let W_USER_UNI = 2.0                                 // 使用者選過此字的次數
let CORRECTION_BOOST = 3                             // 不是第一候選卻被選中：算 3 次
let W_CONTAINED = 0.3                                // （Python 版保留常數，build_data 用）
let MAX_COMPLETIONS = 60

private let SQLITE_TRANSIENT_ = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@inline(__always) func bkey(_ s: String) -> [UInt8] { Array(s.utf8) }

/// 取字串最後 n 個 Unicode 碼點（對應 Python 的 s[-n:]）。
func tailScalars(_ s: String, _ n: Int) -> String {
    let u = Array(s.unicodeScalars)
    if u.count <= n { return s }
    var v = String.UnicodeScalarView()
    v.append(contentsOf: u[(u.count - n)...])
    return String(v)
}

struct Candidate {
    let ch: String
    let code: String
    let exact: Bool
    let score: Double
}

enum ModelError: Error { case open(String) }

final class Model {
    private var db: OpaquePointer?
    private var user: OpaquePointer?
    private var uni: [[UInt8]: Int] = [:]
    private var userUni: [[UInt8]: Int] = [:]
    private var userBi: [[UInt8]: Int] = [:]
    private var ngramCache: [[UInt8]: Int] = [:]

    init(modelDB: String, userDB: String) throws {
        if sqlite3_open_v2(modelDB, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            throw ModelError.open("model.db: \(modelDB)")
        }
        // 讀 uni
        for (c, n) in Model.pairs(db, "select ch, freq from uni") { uni[bkey(c)] = n }
        let dir = (userDB as NSString).deletingLastPathComponent
        if !dir.isEmpty {
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        if sqlite3_open_v2(userDB, &user, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) != SQLITE_OK {
            throw ModelError.open("user.db: \(userDB)")
        }
        sqlite3_exec(user,
            "create table if not exists uni (ch text primary key, n int) without rowid;" +
            "create table if not exists bi (s text primary key, n int) without rowid;", nil, nil, nil)
        for (c, n) in Model.pairs(user, "select ch, n from uni") { userUni[bkey(c)] = n }
        for (c, n) in Model.pairs(user, "select s, n from bi") { userBi[bkey(c)] = n }
    }

    deinit {
        sqlite3_close(db)
        sqlite3_close(user)
    }

    private static func pairs(_ h: OpaquePointer?, _ sql: String) -> [(String, Int)] {
        var st: OpaquePointer?
        var out: [(String, Int)] = []
        guard sqlite3_prepare_v2(h, sql, -1, &st, nil) == SQLITE_OK else { return out }
        defer { sqlite3_finalize(st) }
        while sqlite3_step(st) == SQLITE_ROW {
            out.append((String(cString: sqlite3_column_text(st, 0)), Int(sqlite3_column_int64(st, 1))))
        }
        return out
    }

    // --- 查詢 ---
    private func ngram(_ s: String) -> Int {
        let k = bkey(s)
        if let v = ngramCache[k] { return v }
        var v = 0
        var st: OpaquePointer?
        if sqlite3_prepare_v2(db, "select freq from ngram where s=?", -1, &st, nil) == SQLITE_OK {
            sqlite3_bind_text(st, 1, s, -1, SQLITE_TRANSIENT_)
            if sqlite3_step(st) == SQLITE_ROW { v = Int(sqlite3_column_int64(st, 0)) }
        }
        sqlite3_finalize(st)
        if ngramCache.count > 200_000 { ngramCache.removeAll() }
        ngramCache[k] = v
        return v
    }

    func score(_ ch: String, _ ctx: String) -> Double {
        var s = log1p(Double(uni[bkey(ch)] ?? 0))
        let cs = Array(ctx.unicodeScalars)
        for k in 1...3 {
            if cs.count >= k {
                let f = ngram(tailScalars(ctx, k) + ch)
                if f != 0 {
                    s += W_NGRAM[k]! * log1p(Double(f))
                }
            }
        }
        if !cs.isEmpty {
            var last = String.UnicodeScalarView()
            last.append(cs[cs.count - 1])
            s += W_USER_BI * log1p(Double(userBi[bkey(String(last) + ch)] ?? 0))
        }
        s += W_USER_UNI * log1p(Double(userUni[bkey(ch)] ?? 0))
        return s
    }

    /// 穩定排序（分數高到低，同分保留原序）。
    private static func stableSortDesc(_ a: [Candidate]) -> [Candidate] {
        let idx = a.indices.sorted { i, j in
            if a[i].score != a[j].score { return a[i].score > a[j].score }
            return i < j
        }
        return idx.map { a[$0] }
    }

    func candidates(code: String, ctx ctxIn: String = "") -> [Candidate] {
        if code.isEmpty { return [] }
        let ctx = tailScalars(ctxIn, CTX_LEN)
        var exact: [Candidate] = []
        var st: OpaquePointer?
        if sqlite3_prepare_v2(db, "select code, ch from code where code=? order by rank", -1, &st, nil) == SQLITE_OK {
            sqlite3_bind_text(st, 1, code, -1, SQLITE_TRANSIENT_)
            while sqlite3_step(st) == SQLITE_ROW {
                let c = String(cString: sqlite3_column_text(st, 0))
                let ch = String(cString: sqlite3_column_text(st, 1))
                exact.append(Candidate(ch: ch, code: c, exact: true, score: score(ch, ctx)))
            }
        }
        sqlite3_finalize(st)
        exact = Model.stableSortDesc(exact)
        var seen = Set<[UInt8]>(exact.map { bkey($0.ch) })
        var comp: [Candidate] = []
        st = nil
        if sqlite3_prepare_v2(db,
            "select code, ch from code where code > ? and code < ? order by length(code), rank", -1, &st, nil) == SQLITE_OK {
            sqlite3_bind_text(st, 1, code, -1, SQLITE_TRANSIENT_)
            sqlite3_bind_text(st, 2, code + "{", -1, SQLITE_TRANSIENT_)
            while sqlite3_step(st) == SQLITE_ROW {
                let c = String(cString: sqlite3_column_text(st, 0))
                let ch = String(cString: sqlite3_column_text(st, 1))
                let k = bkey(ch)
                if !seen.contains(k) {
                    seen.insert(k)
                    comp.append(Candidate(ch: ch, code: c, exact: false, score: score(ch, ctx)))
                }
            }
        }
        sqlite3_finalize(st)
        comp = Model.stableSortDesc(comp)
        return exact + Array(comp.prefix(MAX_COMPLETIONS))
    }

    // --- 學習 ---
    private func upsert(_ sql: String, _ key: String, _ n: Int) {
        var st: OpaquePointer?
        if sqlite3_prepare_v2(user, sql, -1, &st, nil) == SQLITE_OK {
            sqlite3_bind_text(st, 1, key, -1, SQLITE_TRANSIENT_)
            sqlite3_bind_int64(st, 2, Int64(n))
            sqlite3_bind_int64(st, 3, Int64(n))
            sqlite3_step(st)
        }
        sqlite3_finalize(st)
    }

    func learn(_ ch: String, prev: String = "", corrected: Bool = false) {
        let n = corrected ? CORRECTION_BOOST : 1
        userUni[bkey(ch), default: 0] += n
        upsert("insert into uni values (?,?) on conflict(ch) do update set n=n+?", ch, n)
        if !prev.isEmpty {
            let s = tailScalars(prev, 1) + ch
            userBi[bkey(s), default: 0] += n
            upsert("insert into bi values (?,?) on conflict(s) do update set n=n+?", s, n)
        }
    }
}
