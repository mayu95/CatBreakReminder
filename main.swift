// CatBreakReminder —— 把"专注工作"做成养成小游戏。
//
// 玩法：
//   · 只要屏幕亮着且在用（主屏/副屏都算，开会也算工作），每累计 20 分钟 = 1 条小鱼干 🐟。
//   · 小鱼干喂给小猫才长「经验」（等级越低一条给的经验越多，升级前期快）；喂食还涨心情。
//   · 太久不喂会变饿、心情下降。
//   · 休息提醒：连续使用 ≥30 分钟，小猫"抗议"提醒你歇会儿并掉心情；
//     但麦克风/摄像头在用、开会、PPT 全屏演示时不打扰，等结束再提醒；离开歇 ≥5 分钟后心情回升。
//   · 小猫平时住在菜单栏弹窗面板里；赚到零食 / 喂食 / 抗议时会滚到屏幕上方。
//
// 纯 Swift 单文件，swiftc 编译，无需 Xcode。详见 build.sh。

import AppKit
import CoreGraphics
import CoreAudio
import CoreMediaIO
import IOKit

// MARK: - 系统状态探测

/// 距上次键鼠输入的空闲秒数（读 IOHIDSystem 的 HIDIdleTime，无需权限）。
func systemIdleSeconds() -> Double {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iterator) == KERN_SUCCESS else { return 0 }
    defer { IOObjectRelease(iterator) }
    let entry = IOIteratorNext(iterator)
    guard entry != 0 else { return 0 }
    defer { IOObjectRelease(entry) }
    var dict: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(entry, &dict, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let props = dict?.takeRetainedValue() as? [String: Any],
          let idleNs = props["HIDIdleTime"] as? UInt64 else { return 0 }
    return Double(idleNs) / 1_000_000_000.0
}

/// 主显示器是否在休眠（黑屏）。
func mainDisplayAsleep() -> Bool {
    return CGDisplayIsAsleep(CGMainDisplayID()) != 0
}

/// 默认输入设备（麦克风）当前是否正在被某进程使用。开会/通话的最强信号。
func microphoneInUse() -> Bool {
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID) == noErr,
          deviceID != 0 else { return false }
    var running = UInt32(0)
    size = UInt32(MemoryLayout<UInt32>.size)
    addr.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
    return AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &running) == noErr && running != 0
}

/// 任意摄像头当前是否正在被使用。
func cameraInUse() -> Bool {
    var addr = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    var dataSize: UInt32 = 0
    guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &dataSize) == noErr, dataSize > 0 else { return false }
    let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
    var devices = [CMIOObjectID](repeating: 0, count: count)
    guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, dataSize, &dataSize, &devices) == noErr else { return false }
    for dev in devices {
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var runAddr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        if CMIOObjectGetPropertyData(dev, &runAddr, 0, nil, size, &size, &running) == noErr, running != 0 { return true }
    }
    return false
}

/// 是否有窗口铺满整块屏幕（PPT 放映 / 全屏演示）。
func fullscreenWindowPresent() -> Bool {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
    let sizes = NSScreen.screens.map { $0.frame.size }
    for info in list {
        guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
              let bDict = info[kCGWindowBounds as String] as? [String: Any],
              let b = CGRect(dictionaryRepresentation: bDict as CFDictionary) else { continue }
        for s in sizes where b.width >= s.width - 1 && b.height >= s.height - 1 { return true }
    }
    return false
}

/// 开会 / 演示中？（仅用于决定"是否打扰提醒休息"，不影响计分。）
func inMeetingOrPresenting() -> Bool {
    return microphoneInUse() || cameraInUse() || fullscreenWindowPresent()
}

// MARK: - 游戏数据模型

final class GameModel {
    private let d = UserDefaults.standard

    // 持久化状态
    var snacks: Int { didSet { d.set(snacks, forKey: "snacks") } }
    var xp: Int { didSet { d.set(xp, forKey: "xp") } }
    var level: Int { didSet { d.set(level, forKey: "level") } }
    var mood: Double { didSet { mood = min(100, max(0, mood)); d.set(mood, forKey: "mood") } }
    var totalFed: Int { didSet { d.set(totalFed, forKey: "totalFed") } }
    var todayProductive: Double { didSet { d.set(todayProductive, forKey: "todayProductive") } }

    // 距下一条小鱼干的累计秒数（持久化，重启不丢）
    var productiveProgress: Double = 0 { didSet { d.set(productiveProgress, forKey: "productiveProgress") } }

    // 瞬时状态（不持久化）
    var statusText: String = "启动中…"
    var isOverworked: Bool = false

    let snackInterval: Double = 20 * 60    // 攒一条小鱼干需要的专注秒数

    private let titles = ["幼猫", "奶猫", "小猫", "少年猫", "成年猫", "猫绅士", "猫老大", "猫王"]

    init() {
        snacks = d.integer(forKey: "snacks")
        xp = d.integer(forKey: "xp")
        level = max(1, d.integer(forKey: "level"))
        mood = d.object(forKey: "mood") == nil ? 60 : d.double(forKey: "mood")
        totalFed = d.integer(forKey: "totalFed")

        // 跨天则重置"今日专注"
        let today = Self.dayString()
        if d.string(forKey: "todayDate") != today {
            d.set(today, forKey: "todayDate")
            d.set(0.0, forKey: "todayProductive")
        }
        todayProductive = d.double(forKey: "todayProductive")
        productiveProgress = d.double(forKey: "productiveProgress")
    }

    static func dayString() -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// 跨天就把"今日专注"归零。每次轮询都调用，处理 app 跨午夜一直开着的情况（不只启动时）。
    func rolloverIfNewDay() {
        let today = Self.dayString()
        if d.string(forKey: "todayDate") != today {
            d.set(today, forKey: "todayDate")
            todayProductive = 0    // didSet 会存盘；小鱼干/经验/等级不受影响
        }
    }

    var title: String { titles[min(level - 1, titles.count - 1)] }
    var xpForNextLevel: Int { level * 50 }

    /// 一条小鱼干喂下去给多少经验：等级越低给得越多（一开始升级快），逐渐变少。
    var xpPerFeed: Int { max(8, 32 - (level - 1) * 4) }

    /// 升级判定。
    private func checkLevelUp() {
        while xp >= xpForNextLevel {
            xp -= xpForNextLevel
            level += 1
        }
    }

    /// 累计专注时间，满 20 分钟产出一条小鱼干。返回这次是否赚到了零食。
    func addProductive(_ seconds: Double) -> Bool {
        todayProductive += seconds
        productiveProgress += seconds
        if productiveProgress >= snackInterval {
            productiveProgress -= snackInterval
            snacks += 1
            return true
        }
        return false
    }

    /// 喂一条小鱼干。返回是否喂成功（有库存）。经验只在这里产生。
    func feed() -> Bool {
        guard snacks > 0 else { return false }
        snacks -= 1
        totalFed += 1
        mood += 25
        xp += xpPerFeed
        checkLevelUp()
        return true
    }

    /// 心情随时间缓慢下降（肚子会饿）。
    func decayMood(_ seconds: Double) { mood -= 0.05 * (seconds / 60) }

    /// 加班抗议，扣心情。
    func overworkPenalty() { mood -= 6 }

    /// 好好休息后心情回升。
    func restRecover() { mood += 12 }

    var moodEmoji: String {
        if isOverworked { return "😾" }
        switch mood {
        case 75...: return "😸"
        case 50..<75: return "😺"
        case 30..<50: return "🐱"
        case 15..<30: return "😿"
        default: return "🙀"
        }
    }

    var moodWord: String {
        if isOverworked { return "抗议中" }
        switch mood {
        case 75...: return "超开心"
        case 50..<75: return "开心"
        case 30..<50: return "一般"
        case 15..<30: return "饿了"
        default: return "饿坏了"
        }
    }

    func save() { d.synchronize() }
}

// MARK: - 进度条

final class BarView: NSView {
    var progress: CGFloat = 0 { didSet { needsDisplay = true } }
    var color: NSColor = .systemGreen

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.height / 2
        NSColor.separatorColor.withAlphaComponent(0.35).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: r, yRadius: r).fill()
        let w = max(bounds.height, bounds.width * min(max(progress, 0), 1))
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: w, height: bounds.height), xRadius: r, yRadius: r).fill()
    }
}

// MARK: - 弹窗面板

final class PanelViewController: NSViewController {
    private let model: GameModel
    var feedAction: (() -> Void)?

    private let catView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let moodBar = BarView()
    private let moodText = NSTextField(labelWithString: "")
    private let xpBar = BarView()
    private let xpText = NSTextField(labelWithString: "")
    private let snackLabel = NSTextField(labelWithString: "")
    private let snackProgressBar = BarView()
    private let snackProgressText = NSTextField(labelWithString: "")
    private let statsText = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let feedButton = NSButton(title: "喂一条小鱼干 🐟", target: nil, action: nil)

    init(model: GameModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let panelWidth: CGFloat = 248
        let container = NSView()

        catView.translatesAutoresizingMaskIntoConstraints = false
        catView.widthAnchor.constraint(equalToConstant: 84).isActive = true
        catView.heightAnchor.constraint(equalToConstant: 84).isActive = true

        titleLabel.font = .boldSystemFont(ofSize: 15)
        titleLabel.alignment = .center
        moodText.font = .systemFont(ofSize: 11)
        xpText.font = .systemFont(ofSize: 11)
        snackLabel.font = .boldSystemFont(ofSize: 14)
        snackProgressText.font = .systemFont(ofSize: 11)
        snackProgressText.textColor = .secondaryLabelColor
        statsText.font = .systemFont(ofSize: 11)
        statsText.textColor = .secondaryLabelColor
        statsText.alignment = .center
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byTruncatingTail

        moodBar.color = .systemPink
        xpBar.color = .systemBlue
        snackProgressBar.color = .systemOrange
        for b in [moodBar, xpBar, snackProgressBar] {
            b.translatesAutoresizingMaskIntoConstraints = false
            b.heightAnchor.constraint(equalToConstant: 9).isActive = true
            b.widthAnchor.constraint(equalToConstant: 140).isActive = true
        }

        feedButton.bezelStyle = .rounded
        feedButton.controlSize = .regular
        feedButton.target = self
        feedButton.action = #selector(feedTapped)

        func row(_ a: NSView, _ b: NSView) -> NSStackView {
            let s = NSStackView(views: [a, b])
            s.orientation = .horizontal
            s.spacing = 8
            a.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            return s
        }

        let stack = NSStackView(views: [
            catView,
            titleLabel,
            row(moodText, moodBar),
            row(xpText, xpBar),
            snackLabel,
            snackProgressBar,
            snackProgressText,
            statsText,
            statusLabel,
            feedButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 5
        stack.setCustomSpacing(8, after: catView)
        stack.setCustomSpacing(8, after: snackProgressText)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: panelWidth),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
        ])
        self.view = container
        container.layoutSubtreeIfNeeded()
        preferredContentSize = container.fittingSize
        refresh()
    }

    @objc private func feedTapped() { feedAction?() }

    func refresh() {
        catView.image = CatArtist.image(level: model.level, mood: model.mood,
                                        overworked: model.isOverworked, side: 84)
        titleLabel.stringValue = "Lv.\(model.level) \(model.title)"
        moodText.stringValue = "心情 \(model.moodWord)"
        moodBar.progress = CGFloat(model.mood / 100)
        xpText.stringValue = "经验 \(model.xp)/\(model.xpForNextLevel)"
        xpBar.progress = CGFloat(Double(model.xp) / Double(model.xpForNextLevel))
        snackLabel.stringValue = "🐟 小鱼干 × \(model.snacks)"
        let mins = Int(model.productiveProgress / 60)
        let total = Int(model.snackInterval / 60)
        snackProgressBar.progress = CGFloat(model.productiveProgress / model.snackInterval)
        snackProgressText.stringValue = "距下一条：专注 \(mins) / \(total) 分钟"
        let tMin = Int(model.todayProductive / 60)
        let blocks = Int(model.todayProductive / model.snackInterval)
        statsText.stringValue = "今日专注 \(tMin / 60)h\(tMin % 60)m　·　今日 \(blocks) 个 20 分钟"
        statusLabel.stringValue = model.statusText
        feedButton.isEnabled = model.snacks > 0
        preferredContentSize = view.fittingSize
    }
}

// MARK: - 小黑猫玩球浮层（走过来 → 拨球 → 溜走，所有屏幕同时出现）

final class CatOverlay {
    private var windows: [NSWindow] = []
    private var showing = false

    func show(message: String) {
        guard !showing else { return }
        showing = true
        let screens = NSScreen.screens.isEmpty ? [NSScreen.main].compactMap { $0 } : NSScreen.screens
        let cat = resolveCat()
        let dwell = 3.0   // 20 分钟那只：不压暗，停 3 秒
        windows = screens.map {
            present(on: $0, message: message, frames: cat.frames, aspect: cat.aspect, pixelated: cat.pixelated, dwell: dwell)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0 + dwell + 2.4) { [weak self] in
            self?.windows.forEach { $0.orderOut(nil) }
            self?.windows = []
            self?.showing = false
        }
    }

    /// 优先用 assets 里的猫图（朝左 → 镜像成朝右）；找不到才用代码画的兜底。
    private var cachedCat: (frames: [Any], aspect: CGFloat, pixelated: Bool)?

    private func resolveCat() -> (frames: [Any], aspect: CGFloat, pixelated: Bool) {
        if let c = cachedCat { return c }   // 只读图/对齐一次，之后复用
        let result = loadAndNormalizeCat()
        cachedCat = result
        return result
    }

    private func loadAndNormalizeCat() -> (frames: [Any], aspect: CGFloat, pixelated: Bool) {
        var imgs: [NSImage] = []
        // cat.png 作为第 0 帧（若有）
        if let url = Bundle.main.url(forResource: "cat", withExtension: "png"), let img = NSImage(contentsOf: url) {
            imgs.append(img)
        }
        // 后续帧 cat_1.png, cat_2.png …（没有 cat.png 时则从 cat_0.png 开始）
        var i = imgs.isEmpty ? 0 : 1
        while let url = Bundle.main.url(forResource: "cat_\(i)", withExtension: "png"), let img = NSImage(contentsOf: url) {
            imgs.append(img); i += 1
        }
        // 只用背景透明的帧；不透明（带烤进去的白底/格子底）的帧会闪方块，自动跳过
        let usable = imgs.filter { hasTransparentBackground($0) }
        if !usable.isEmpty {
            let n = normalizedFrames(usable)
            if !n.frames.isEmpty { return (n.frames, n.aspect, false) }
        }
        // 兜底
        let drawn = (0..<4).compactMap {
            CatArtist.kitten(frame: $0).cgImage(forProposedRect: nil, context: nil, hints: nil) as Any?
        }
        return (drawn, CGFloat(CatArtist.spriteW) / CGFloat(CatArtist.spriteH), true)
    }

    /// 把多帧对齐成同尺寸：抠出每帧里猫的轮廓 → 统一高度、底部对齐、水平居中 → 镜像朝右。
    /// 这样即使各帧原图裁切/大小不同，走起来也不会忽大忽小地跳。
    private func normalizedFrames(_ imgs: [NSImage]) -> (frames: [Any], aspect: CGFloat) {
        var crops: [(cg: CGImage, w: Int, h: Int)] = []
        for img in imgs {
            guard let rep = rgbaRep(img, maxH: 320), let data = rep.bitmapData, let cg = rep.cgImage else { continue }
            let pw = rep.pixelsWide, ph = rep.pixelsHigh, bpr = rep.bytesPerRow, spp = rep.samplesPerPixel
            var minX = pw, minY = ph, maxX = -1, maxY = -1
            for y in 0..<ph {
                let row = data + y * bpr
                for x in 0..<pw where row[x * spp + 3] > 25 {   // alpha > ~0.1
                    if x < minX { minX = x }; if x > maxX { maxX = x }
                    if y < minY { minY = y }; if y > maxY { maxY = y }
                }
            }
            guard maxX >= minX, maxY >= minY,
                  let cropped = cg.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
            else { continue }
            crops.append((cropped, maxX - minX + 1, maxY - minY + 1))
        }
        guard !crops.isEmpty else { return ([], 1) }

        let targetH = CGFloat(crops.map { $0.h }.max()!)
        let scaledWs = crops.map { CGFloat($0.w) * targetH / CGFloat($0.h) }
        let canvasW = scaledWs.max()!, canvasH = targetH

        var frames: [Any] = []
        for (i, c) in crops.enumerated() {
            let out = NSImage(size: NSSize(width: canvasW, height: canvasH))
            out.lockFocus()
            let sw = scaledWs[i]
            NSImage(cgImage: c.cg, size: NSSize(width: c.w, height: c.h))
                .draw(in: NSRect(x: (canvasW - sw) / 2, y: 0, width: sw, height: targetH))
            out.unlockFocus()
            if let mcg = mirrored(out).cgImage(forProposedRect: nil, context: nil, hints: nil) {
                frames.append(mcg)
            }
        }
        return (frames, canvasW / canvasH)
    }

    /// 把 NSImage 画进一个已知 RGBA8 位图（限制高度，便于扫描像素）。
    private func rgbaRep(_ img: NSImage, maxH: CGFloat) -> NSBitmapImageRep? {
        let aspect = img.size.width / max(img.size.height, 1)
        let ph = max(1, Int(min(maxH, max(img.size.height, 1))))
        let pw = max(1, Int(CGFloat(ph) * aspect))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: pw * 4, bitsPerPixel: 32) else { return nil }
        rep.size = NSSize(width: pw, height: ph)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(x: 0, y: 0, width: pw, height: ph))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// 四角是否透明（判断这张图背景是不是真透明，过滤掉烤进白底/格子底的图）。
    private func hasTransparentBackground(_ img: NSImage) -> Bool {
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return true }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        for (x, y) in [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)] {
            if let c = rep.colorAt(x: x, y: y), c.alphaComponent < 0.5 { return true }
        }
        return false
    }

    /// 水平镜像（保留透明）。
    private func mirrored(_ img: NSImage) -> NSImage {
        let size = img.size
        let out = NSImage(size: size)
        out.lockFocus()
        let t = NSAffineTransform()
        t.translateX(by: size.width, yBy: 0)
        t.scaleX(by: -1, yBy: 1)
        t.concat()
        img.draw(at: .zero, from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1)
        out.unlockFocus()
        return out
    }

    private func present(on screen: NSScreen, message: String, frames: [Any], aspect: CGFloat, pixelated: Bool, dim: Bool = false, dwell: Double = 3.0) -> NSWindow {
        let sf = screen.frame
        // 休息提醒：窗口铺满整屏（好做整屏压暗）；普通庆祝：只占顶部一条
        let H: CGFloat = dim ? sf.height : 280
        let frame = dim ? sf : NSRect(x: sf.minX, y: sf.maxY - H, width: sf.width, height: H)

        let win = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false; win.backgroundColor = .clear; win.hasShadow = false
        win.level = .screenSaver; win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        win.contentView = content
        let w = frame.width

        // 休息提醒的柔和压暗背景（在最底层）
        var dimLayer: CALayer?
        if dim {
            let d = CALayer()
            d.frame = content.bounds
            d.backgroundColor = NSColor.black.cgColor
            d.opacity = 0
            content.layer?.addSublayer(d)
            dimLayer = d
        }

        let catH: CGFloat = 75      // 猫的高度（比之前小一半）
        let catW = catH * aspect
        let catY = dim ? (frame.height - 150) : (H * 0.44)
        let centerX = w / 2

        let kitten = CALayer()
        kitten.contents = frames.first
        if pixelated { kitten.magnificationFilter = .nearest }   // 像素图放大保持颗粒；真实图用默认平滑
        kitten.contentsGravity = .resizeAspect
        kitten.bounds = CGRect(x: 0, y: 0, width: catW, height: catH)
        kitten.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        kitten.position = CGPoint(x: -catW, y: catY)
        content.layer?.addSublayer(kitten)

        // 毛线团：摆在猫前方（右侧）一点
        let ballSize: CGFloat = 46
        let ballRestX = centerX + catW * 0.42
        let ballY = catY - catH * 0.26
        let ball = CALayer()
        ball.contents = CatArtist.ball(side: ballSize).cgImage(forProposedRect: nil, context: nil, hints: nil)
        ball.contentsGravity = .resizeAspect
        ball.bounds = CGRect(x: 0, y: 0, width: ballSize, height: ballSize)
        ball.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        ball.position = CGPoint(x: ballRestX, y: ballY)
        ball.opacity = 0
        content.layer?.addSublayer(ball)

        let bubble = makeBubble(text: message, scale: screen.backingScaleFactor)
        bubble.opacity = 0
        let bubbleX = min(centerX + catW * 0.45 + bubble.bounds.width / 2,
                          w - bubble.bounds.width / 2 - 12)
        bubble.position = CGPoint(x: bubbleX, y: catY + catH * 0.5 + 6)
        content.layer?.addSublayer(bubble)

        win.orderFrontRegardless()
        if let d = dimLayer { fade(d, to: 0.34, dur: 0.5) }   // 压暗淡入

        // 1) 走到屏幕中央（匀速 + 走路帧 + 轻微起伏）
        addBob(kitten, dur: 2.0)
        addWalk(kitten, frames: frames, dur: 2.0)
        moveX(kitten, to: centerX, dur: 2.0, timing: .linear) {
            kitten.removeAnimation(forKey: "walk")
            kitten.contents = frames.first
            self.addIdle(kitten)
            self.fade(bubble, to: 1, dur: 0.3)
            // 2) 停留：气泡 + 毛线团出现，猫"拨着玩"
            self.fade(ball, to: 1, dur: 0.25)
            self.playBall(ball, baseX: ballRestX, baseY: ballY, dwell: dwell)
            DispatchQueue.main.asyncAfter(deadline: .now() + dwell) {
                kitten.removeAnimation(forKey: "idle")
                self.fade(bubble, to: 0, dur: 0.3)
                if let d = dimLayer { self.fade(d, to: 0, dur: 0.6) }   // 压暗淡出
                // 3) 猫追着毛线团一起往右走出去
                self.rollBallOff(ball, fromX: ballRestX, baseY: ballY, toX: w + ballSize)
                self.addBob(kitten, dur: 1.8)
                self.addWalk(kitten, frames: frames, dur: 1.8)
                self.moveX(kitten, to: w + catW, dur: 1.8, timing: .linear, done: nil)
            }
        }
        return win
    }

    /// 停留时毛线团被"拨着玩"：一蹦一蹦 + 左右晃 + 微转。
    private func playBall(_ ball: CALayer, baseX: CGFloat, baseY: CGFloat, dwell: Double) {
        let period = 1.2
        let hop = CAKeyframeAnimation(keyPath: "position.y")
        hop.values = [baseY, baseY + 22, baseY, baseY + 12, baseY]
        hop.keyTimes = [0, 0.25, 0.5, 0.72, 1]
        hop.duration = period
        hop.repeatCount = Float(dwell / period)
        ball.add(hop, forKey: "hop")
        let wig = CAKeyframeAnimation(keyPath: "position.x")
        wig.values = [baseX, baseX + 8, baseX - 5, baseX]
        wig.duration = period
        wig.repeatCount = Float(dwell / period)
        ball.add(wig, forKey: "wig")
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = -0.25; spin.toValue = 0.25
        spin.duration = period / 2; spin.autoreverses = true
        spin.repeatCount = Float(dwell / (period / 2))
        ball.add(spin, forKey: "spin")
    }

    /// 毛线团弹跳着滚出屏幕。
    private func rollBallOff(_ ball: CALayer, fromX: CGFloat, baseY: CGFloat, toX: CGFloat) {
        let bounces: [CGFloat] = [0, 30, 0, 18, 0, 8, 0]
        var pts: [NSValue] = []
        for i in 0..<bounces.count {
            let t = CGFloat(i) / CGFloat(bounces.count - 1)
            pts.append(NSValue(point: NSPoint(x: fromX + (toX - fromX) * t, y: baseY + bounces[i])))
        }
        let pos = CAKeyframeAnimation(keyPath: "position")
        pos.values = pts; pos.duration = 1.6; pos.timingFunction = CAMediaTimingFunction(name: .easeIn)
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0; spin.toValue = -4 * Double.pi; spin.duration = 1.6
        CATransaction.begin()
        ball.position = NSPoint(x: toX, y: baseY)
        ["hop", "wig", "spin"].forEach { ball.removeAnimation(forKey: $0) }
        ball.add(pos, forKey: "rolloff"); ball.add(spin, forKey: "spin")
        CATransaction.commit()
    }

    /// 多帧腿姿轮换 = 走路。
    private func addWalk(_ l: CALayer, frames: [Any], dur: Double) {
        guard frames.count >= 2 else { return }
        let a = CAKeyframeAnimation(keyPath: "contents")
        a.values = frames
        a.calculationMode = .discrete
        a.duration = 0.5
        a.repeatCount = Float(dur / 0.5)
        l.add(a, forKey: "walk")
    }

    /// 停留时的轻微呼吸/摆动。
    private func addIdle(_ l: CALayer) {
        let a = CABasicAnimation(keyPath: "transform.translation.y")
        a.fromValue = 0; a.toValue = 3
        a.duration = 1.1; a.autoreverses = true; a.repeatCount = .infinity
        l.add(a, forKey: "idle")
    }

    // MARK: 休息提醒（整屏柔和压暗 + 玩球的猫走过来）

    func showRest(minutes: Int) {
        guard !showing else { return }
        showing = true
        let screens = NSScreen.screens.isEmpty ? [NSScreen.main].compactMap { $0 } : NSScreen.screens
        let cat = resolveCat()
        let msg = "该休息一下啦 🐾 已专注 \(minutes) 分钟"
        let dwell = 5.0   // 45 分钟那只：压暗，停 5 秒
        windows = screens.map {
            present(on: $0, message: msg, frames: cat.frames, aspect: cat.aspect, pixelated: cat.pixelated, dim: true, dwell: dwell)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0 + dwell + 2.4) { [weak self] in
            self?.windows.forEach { $0.orderOut(nil) }
            self?.windows = []
            self?.showing = false
        }
    }

    // MARK: 动画基元

    private func moveX(_ l: CALayer, to x: CGFloat, dur: Double, timing: CAMediaTimingFunctionName, done: (() -> Void)?) {
        let a = CABasicAnimation(keyPath: "position.x")
        a.fromValue = l.presentation()?.position.x ?? l.position.x
        a.toValue = x
        a.duration = dur
        a.timingFunction = CAMediaTimingFunction(name: timing)
        CATransaction.begin()
        CATransaction.setCompletionBlock(done)
        l.position.x = x
        l.add(a, forKey: "mv")
        CATransaction.commit()
    }

    /// 走路的上下颠簸。
    private func addBob(_ l: CALayer, dur: Double) {
        let bob = CAKeyframeAnimation(keyPath: "transform.translation.y")
        bob.values = [0, 4, 0, 4, 0, 4, 0]
        bob.keyTimes = [0, 0.16, 0.33, 0.5, 0.66, 0.83, 1]
        bob.duration = dur
        l.add(bob, forKey: "bob")
    }

    private func makeBubble(text: String, scale: CGFloat) -> CALayer {
        let font = NSFont.systemFont(ofSize: 18, weight: .medium)
        let size = (text as NSString).size(withAttributes: [.font: font])
        let pad: CGFloat = 18
        let w = ceil(size.width) + pad * 2, h = ceil(size.height) + pad * 1.4
        let bubble = CALayer()
        bubble.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        bubble.backgroundColor = NSColor.white.withAlphaComponent(0.96).cgColor
        bubble.cornerRadius = 16
        bubble.shadowColor = NSColor.black.cgColor; bubble.shadowOpacity = 0.18
        bubble.shadowRadius = 8; bubble.shadowOffset = CGSize(width: 0, height: -2)
        let label = CATextLayer()
        label.string = text; label.font = font; label.fontSize = 18
        label.foregroundColor = NSColor.black.cgColor; label.alignmentMode = .center
        label.contentsScale = scale
        label.frame = CGRect(x: 0, y: (h - size.height) / 2 - 1, width: w, height: size.height + 2)
        bubble.addSublayer(label)
        return bubble
    }

    private func fade(_ l: CALayer, to v: Float, dur: Double) {
        let a = CABasicAnimation(keyPath: "opacity"); a.fromValue = l.opacity; a.toValue = v; a.duration = dur
        l.opacity = v; l.add(a, forKey: "fade")
    }
}

// MARK: - 主控制器

final class AppController: NSObject, NSApplicationDelegate {
    private let model = GameModel()
    private let overlay = CatOverlay()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var panel: PanelViewController!

    private let tick: TimeInterval = 60   // 轮询间隔：1 分钟（很省 CPU）
    private let idleReset: TimeInterval = 5 * 60       // 空闲多久算"休息"
    private let overworkThreshold: TimeInterval = 45 * 60   // 连续使用多久开始提醒休息（压暗弹窗）
    private let protestGap: TimeInterval = 10 * 60     // 两次提醒最小间隔

    private var continuousActive: TimeInterval = 0     // 连续未休息时长
    private var lastTick = Date()
    private var lastProtest = Date.distantPast

    func applicationDidFinishLaunching(_ n: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        panel = PanelViewController(model: model)
        panel.feedAction = { [weak self] in self?.feed() }
        popover.contentViewController = panel
        popover.behavior = .transient

        lastTick = Date()
        let t = Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { [weak self] _ in self?.onTick() }
        RunLoop.main.add(t, forMode: .common)
    }

    private func catImage(side: CGFloat) -> NSImage {
        CatArtist.image(level: model.level, mood: model.mood, overworked: model.isOverworked, side: side)
    }

    private func updateStatusIcon() {
        let img = catImage(side: 20)
        img.isTemplate = false
        statusItem.button?.image = img
        statusItem.button?.title = ""   // 小鱼干数量显示在面板里，菜单栏只放猫图标
    }

    private func onTick() {
        model.rolloverIfNewDay()   // 跨午夜归零今日专注

        let now = Date()
        let delta = now.timeIntervalSince(lastTick)
        lastTick = now

        let idle = systemIdleSeconds()
        let meeting = inMeetingOrPresenting()
        // "屏幕亮着 + 在用" 就算工作：有键鼠输入，或正在开会/演示（即使没敲键盘）。
        // 主屏副屏都算；屏幕休眠则不算。
        let active = !mainDisplayAsleep() && (idle < idleReset || meeting)

        model.decayMood(delta)

        if !active {
            // 离开/休息：心情回升，清零连续计时。
            if continuousActive >= overworkThreshold { model.restRecover() }
            continuousActive = 0
            model.isOverworked = false
            model.statusText = mainDisplayAsleep() ? "💤 屏幕已休眠" : "💤 离开中（已休息）"
        } else {
            continuousActive += delta

            // 计分：任何使用都加分（开会也算工作）。
            if model.addProductive(delta) {
                overlay.show(message: "叮！专注满 20 分钟，获得一条小鱼干 🐟")
            }

            // 休息提醒：连续 30 分钟提醒；但开会/摄像头/麦克风/PPT 全屏时不打扰，憋到结束再提醒。
            if continuousActive >= overworkThreshold {
                model.isOverworked = true
                if meeting {
                    model.statusText = "🎤 开会/演示中（计入工作，先不打扰）"
                } else {
                    model.statusText = "😾 该歇歇了（已连续 \(Int(continuousActive/60)) 分钟）"
                    if now.timeIntervalSince(lastProtest) >= protestGap {
                        lastProtest = now
                        model.overworkPenalty()
                        overlay.showRest(minutes: Int(continuousActive / 60))
                    }
                }
            } else {
                model.statusText = meeting ? "🎤 开会/演示中（计入工作）" : "✅ 使用中（计入专注）"
            }
        }

        updateStatusIcon()
        model.save()
        if popover.isShown { panel.refresh() }
    }

    private func feed() {
        if model.feed() {
            overlay.show(message: "好好吃喵～谢谢投喂！")
        }
        updateStatusIcon()
        model.save()
        panel.refresh()
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            panel.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "🐾 测试一下小猫", action: #selector(testCat), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        }
    }

    @objc private func testCat() {
        overlay.show(message: "喵～这是一次测试！")
    }
}

// MARK: - 启动

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = AppController()
app.delegate = controller
app.run()
