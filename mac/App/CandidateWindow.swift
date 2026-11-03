import Cocoa

/// 自己畫的候選字窗：不用 IMKCandidates（顯示時會攔截數字鍵、方向鍵，跟 Composer 搶按鍵）。
/// 也拿來短暫顯示「中／英」。
final class CandidateWindow {
    /// CJLEARN_NO_UI=1（外殼測試）：不開視窗，只記錄要顯示的內容
    static let headless = ProcessInfo.processInfo.environment["CJLEARN_NO_UI"] != nil
    private(set) var shown: [(String, String)] = []
    private(set) var flashed = ""
    private lazy var panel: NSPanel = makePanel()
    private let label = NSTextField(labelWithString: "")
    private var hideTimer: Timer?
    private let font = NSFont.systemFont(ofSize: 18)
    private let hintFont = NSFont.systemFont(ofSize: 13)

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        box.layer?.cornerRadius = 6
        box.layer?.borderWidth = 0.5
        box.layer?.borderColor = NSColor.separatorColor.cgColor
        label.maximumNumberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -5),
        ])
        panel.contentView = box
        return panel
    }

    /// items：(候選字, 灰字提示)；cursor：頁內游標。
    func show(items: [(String, String)], cursor: Int, caret: NSRect) {
        shown = items
        if Self.headless { return }
        let text = NSMutableAttributedString()
        for (i, item) in items.enumerated() {
            if i > 0 { text.append(NSAttributedString(string: "\n")) }
            let selected = i == cursor
            let main: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: selected ? NSColor.selectedMenuItemTextColor : NSColor.labelColor,
                .backgroundColor: selected ? NSColor.controlAccentColor : NSColor.clear,
            ]
            text.append(NSAttributedString(string: "\(i + 1) \(item.0)", attributes: main))
            if !item.1.isEmpty {
                text.append(NSAttributedString(string: " \(item.1)",
                                               attributes: [.font: hintFont, .foregroundColor: NSColor.secondaryLabelColor]))
            }
        }
        present(text, caret: caret, autoHide: nil)
    }

    func flash(_ s: String, caret: NSRect) {
        flashed = s
        if Self.headless { return }
        present(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor.labelColor]),
                caret: caret, autoHide: 0.8)
    }

    func hide() {
        shown = []
        if Self.headless { return }
        hideTimer?.invalidate()
        hideTimer = nil
        panel.orderOut(nil)
    }

    private func present(_ text: NSAttributedString, caret: NSRect, autoHide: TimeInterval?) {
        hideTimer?.invalidate()
        hideTimer = nil
        label.attributedStringValue = text
        let size = label.fittingSize
        let w = size.width + 16, h = size.height + 10
        // 放在游標下方；超出螢幕就改放上方、往左推
        let screen = NSScreen.screens.first { $0.frame.contains(caret.origin) } ?? NSScreen.main
        let vis = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = caret.minX, y = caret.minY - h - 4
        if y < vis.minY { y = caret.maxY + 4 }
        x = min(max(x, vis.minX), vis.maxX - w)
        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        panel.orderFrontRegardless()
        if let t = autoHide {
            hideTimer = Timer.scheduledTimer(withTimeInterval: t, repeats: false) { [weak self] _ in self?.hide() }
        }
    }
}
