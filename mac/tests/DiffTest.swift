// 差分測試：讀 cases.json（Python 版預期結果），用 Swift 版跑同樣按鍵序列比對。
// 用法：./difftest <model.db> <cases.json> <新的user.db路徑>
import Foundation

@main
struct DiffTest {
    static func main() {

        let args = CommandLine.arguments
        guard args.count >= 4 else { print("usage: difftest model.db cases.json user.db"); exit(2) }
        try? FileManager.default.removeItem(atPath: args[3])
        let data = try! Data(contentsOf: URL(fileURLWithPath: args[2]))
        let cases = try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        let model = try! Model(modelDB: args[1], userDB: args[3])

        func b(_ s: String) -> [UInt8] { Array(s.utf8) }

        var pass = 0
        var failDetail: String? = nil
        var failCount = 0
        for (ci, cs) in cases.enumerated() {
            let keys = cs["keys"] as! [[Any]]
            let steps = cs["steps"] as! [[Any]]
            let comp = Composer(model: model)
            comp.fullPunct = (cs["full_punct"] as? NSNumber)?.boolValue ?? false
            var bad: String? = nil
            for (i, k) in keys.enumerated() {
                let r = comp.process(k[0] as! String, ctrl: (k[1] as! NSNumber).boolValue,
                                     shift: (k[2] as! NSNumber).boolValue, alt: (k[3] as! NSNumber).boolValue,
                                     release: (k[4] as! NSNumber).boolValue)
                let e = steps[i]
                let got: [String] = [r.handled ? "1" : "0", r.commit, comp.code, String(comp.page), String(comp.cursor), comp.chinese ? "1" : "0"]
                let exp: [String] = [(e[0] as! NSNumber).stringValue, e[1] as! String, e[2] as! String,
                                     (e[3] as! NSNumber).stringValue, (e[4] as! NSNumber).stringValue, (e[5] as! NSNumber).stringValue]
                let pcs = comp.pageCands()
                let expPage = e[6] as! String
                let expScores = (e[7] as! [NSNumber]).map { $0.doubleValue }
                var scoreBad = pcs.count != expScores.count
                if !scoreBad { for (x, y) in zip(pcs, expScores) where abs(x.score - y) > 1e-9 { scoreBad = true } }
                if got.map(b) != exp.map(b) || b(pcs.map { $0.ch }.joined()) != b(expPage) || scoreBad {
                    bad = "case \(ci) step \(i) key=\(k)\n  expected [handled,commit,code,page,cursor,chinese]=\(exp)\n  got      \(got) page=\(pcs.map { $0.ch }.joined()) scores=\(pcs.map { $0.score })\n  exp page=\(expPage) scores=\(expScores)"
                    break
                }
            }
            if bad == nil {
                let pe = cs["preedit"] as! String, pc = cs["page"] as! String, cx = cs["ctx"] as! String
                if b(comp.preedit()) != b(pe) || b(comp.pageCands().map { $0.ch }.joined()) != b(pc) || b(comp.ctx) != b(cx) {
                    bad = "case \(ci) final state: expected preedit=\(pe) page=\(pc) ctx=\(cx); got preedit=\(comp.preedit()) page=\(comp.pageCands().map { $0.ch }.joined()) ctx=\(comp.ctx)\n  keys=\(keys)"
                }
            }
            if let d = bad {
                failCount += 1
                if failDetail == nil { failDetail = d }
            } else { pass += 1 }
        }
        if let d = failDetail { print("FIRST MISMATCH:\n\(d)") }
        print("PASSED \(pass)/\(cases.count) (failed \(failCount))")
        exit(failCount == 0 ? 0 : 1)

    }
}
