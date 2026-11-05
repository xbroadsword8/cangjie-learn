import Foundation

/// 學習資料同步的輸入法端（對應 cjlearn/sync.py 的 read_peers、PeerWatcher、status_text）。
/// 輸入法本身不連網：git 推拉由 launchd 每 15 分鐘跑的 sync.py 負責，這裡只讀 data_dir/sync/ 的檔案。
enum Sync {
    /// JSON 的整數（不收 true／false、小數），跟 Python 的 type(n) is int 一樣
    private static func intValue(_ v: Any) -> Int? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), !CFNumberIsFloatType(n) else { return nil }
        return n.intValue
    }

    private static func json(_ path: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func readPeers(_ dir: String, selfName: String) -> (uni: [String: Int], bi: [String: Int]) {
        var uni: [String: Int] = [:], bi: [String: Int] = [:]
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".json") }.sorted()
        for f in files where String(f.dropLast(5)) != selfName {
            guard let d = json(dir + "/" + f) else { continue }
            for (key, apply) in [("uni", { (k: String, n: Int) in uni[k, default: 0] += n }),
                                 ("bi", { (k: String, n: Int) in bi[k, default: 0] += n })] {
                guard let m = d[key] as? [String: Any] else { continue }
                for (k, v) in m { if let n = intValue(v), n > 0 { apply(k, n) } }
            }
        }
        return (uni, bi)
    }

    /// sync/ 有變動才重讀；最多每 interval 秒檢查一次。
    final class PeerWatcher {
        let dataDir: String
        let interval: TimeInterval
        private var next = Date.distantPast
        private var sig = ""
        init(dataDir: String, interval: TimeInterval = 60) { self.dataDir = dataDir; self.interval = interval }

        @discardableResult func poll(_ model: Model) -> Bool {
            let now = Date()
            if now < next { return false }
            next = now.addingTimeInterval(interval)
            let name = (Sync.json(dataDir + "/settings.json")?["sync_name"] as? String) ?? ""
            let dir = dataDir + "/sync"
            let fm = FileManager.default
            var s = name
            for f in ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter({ $0.hasSuffix(".json") }).sorted() {
                let a = try? fm.attributesOfItem(atPath: dir + "/" + f)
                s += "|\(f):\((a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0):\((a?[.size] as? Int) ?? 0)"
            }
            if s == sig { return false }
            sig = s
            let p: (uni: [String: Int], bi: [String: Int]) = name.isEmpty ? ([:], [:]) : Sync.readPeers(dir, selfName: name)
            model.setPeers(uni: p.uni, bi: p.bi)
            return true
        }
    }

    /// 給輸入法選單用的一行字；沒設定同步回傳空字串。
    static func statusText(_ dataDir: String, now: Date = Date()) -> String {
        guard let remote = json(dataDir + "/settings.json")?["sync_remote"] as? String, !remote.isEmpty else { return "" }
        guard let st = json(dataDir + "/sync_status.json") else { return "同步：還沒執行過" }
        func ago(_ t: Double) -> String {
            let m = Int((now.timeIntervalSince1970 - t) / 60)
            return m < 1 ? "剛剛" : m < 60 ? "\(m) 分鐘前" : m < 2880 ? "\(m / 60) 小時前" : "\(m / 1440) 天前"
        }
        let time = (st["time"] as? NSNumber)?.doubleValue ?? 0
        if (st["ok"] as? Bool) == true { return "同步：\(ago(time))成功" }
        let lastOK = (st["last_ok"] as? NSNumber)?.doubleValue ?? 0
        let last = lastOK > 0 ? "（上次成功 \(ago(lastOK))）" : "（從沒成功過）"
        return "⚠ 同步失敗\(last)：\(String(((st["message"] as? String) ?? "").prefix(60)))"
    }
}
