// CatArtist —— 用 Core Graphics 手绘不同等级 / 不同心情的猫头像，替代丑 emoji。
// 同一套绘制同时用于：弹窗大头像、菜单栏小图标、滚猫浮层。

import AppKit

enum CatExpression { case happy, content, neutral, sad, angry }

struct CatArtist {

    static func expression(mood: Double, overworked: Bool) -> CatExpression {
        if overworked { return .angry }
        switch mood {
        case 75...: return .happy
        case 50..<75: return .content
        case 30..<50: return .neutral
        default: return .sad
        }
    }

    /// 等级毛色。
    static func furColor(level: Int) -> NSColor {
        let palette: [NSColor] = [
            NSColor(srgbRed: 0.80, green: 0.80, blue: 0.84, alpha: 1),  // 1 幼猫 浅灰
            NSColor(srgbRed: 0.96, green: 0.86, blue: 0.70, alpha: 1),  // 2 奶猫 奶油
            NSColor(srgbRed: 0.95, green: 0.64, blue: 0.30, alpha: 1),  // 3 小猫 橘
            NSColor(srgbRed: 0.72, green: 0.48, blue: 0.25, alpha: 1),  // 4 少年猫 棕
            NSColor(srgbRed: 0.57, green: 0.65, blue: 0.71, alpha: 1),  // 5 成年猫 灰蓝
            NSColor(srgbRed: 0.34, green: 0.34, blue: 0.39, alpha: 1),  // 6 猫绅士 炭灰
            NSColor(srgbRed: 0.91, green: 0.72, blue: 0.16, alpha: 1),  // 7 猫老大 金
            NSColor(srgbRed: 0.17, green: 0.17, blue: 0.20, alpha: 1),  // 8 猫王 黑
        ]
        return palette[min(max(level - 1, 0), palette.count - 1)]
    }

    static func image(level: Int, mood: Double, overworked: Bool, side: CGFloat) -> NSImage {
        let scale: CGFloat = 2
        let px = Int(side * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: side, height: side)

        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = ctx
        // rep.size 已把坐标系设为「点」，直接按 side 绘制即可（retina 由 pixelsWide 负责）。
        draw(level: level, mood: mood, overworked: overworked, S: side)
        NSGraphicsContext.restoreGraphicsState()

        let img = NSImage(size: NSSize(width: side, height: side))
        img.addRepresentation(rep)
        return img
    }

    /// 通用离屏渲染：在 0..side 的点坐标系里绘制。
    static func render(width: CGFloat, height: CGFloat, _ body: () -> Void) -> NSImage {
        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        body()
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: NSSize(width: width, height: height))
        img.addRepresentation(rep)
        return img
    }

    /// 一只可爱的小黑猫（全身、坐姿），用于"走过来玩球"的提醒动画。
    // 像素 sprite 画布尺寸
    static let spriteW = 46
    static let spriteH = 28

    /// 像素风、写实比例的走路灰猫（侧身朝右）。frame 0..3 是走路循环的四帧（腿在迈步）。
    /// 关闭抗锯齿、低分辨率渲染 → 放大后是像素颗粒感。
    static func kitten(frame: Int) -> NSImage {
        let W = spriteW, H = spriteH
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: W, height: H)
        NSGraphicsContext.saveGraphicsState()
        let g = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = g
        g.shouldAntialias = false
        g.imageInterpolation = .none
        drawCatSprite(frame: frame, W: CGFloat(W), H: CGFloat(H))
        NSGraphicsContext.restoreGraphicsState()
        let img = NSImage(size: NSSize(width: W, height: H))
        img.addRepresentation(rep)
        return img
    }

    private static func drawCatSprite(frame: Int, W: CGFloat, H: CGFloat) {
        let body = NSColor(srgbRed: 0.45, green: 0.45, blue: 0.50, alpha: 1)
        let shade = NSColor(srgbRed: 0.33, green: 0.33, blue: 0.38, alpha: 1)
        let dark = NSColor(srgbRed: 0.18, green: 0.18, blue: 0.22, alpha: 1)
        let eye = NSColor(srgbRed: 0.97, green: 0.76, blue: 0.05, alpha: 1)

        // 尾巴
        let tail = NSBezierPath()
        tail.move(to: CGPoint(x: W * 0.24, y: H * 0.42))
        tail.curve(to: CGPoint(x: W * 0.05, y: H * 0.78),
                   controlPoint1: CGPoint(x: W * 0.10, y: H * 0.36),
                   controlPoint2: CGPoint(x: W * 0.00, y: H * 0.60))
        tail.lineWidth = H * 0.11; tail.lineCapStyle = .round
        shade.setStroke(); tail.stroke()

        // 腿：四条，按帧迈步
        let frames: [[CGFloat]] = [
            [0.05, -0.03, -0.03, 0.05],   // 对角步 A
            [0.02, 0.02, 0.02, 0.02],     // 经过
            [-0.03, 0.05, 0.05, -0.03],   // 对角步 B
            [0.02, 0.02, 0.02, 0.02],
        ]
        let off = frames[((frame % 4) + 4) % 4]
        let groundY = H * 0.04, hipY = H * 0.46
        let legW = H * 0.085
        let backHipX = W * 0.33, frontHipX = W * 0.72
        // (hipX, pawOffset, color)
        let legs: [(CGFloat, CGFloat, NSColor)] = [
            (backHipX - W * 0.02, off[0], dark),     // 后远腿
            (frontHipX - W * 0.02, off[2], dark),    // 前远腿
            (backHipX + W * 0.03, off[1], shade),    // 后近腿
            (frontHipX + W * 0.03, off[3], body),    // 前近腿
        ]
        for (hipX, pawOff, col) in legs {
            let p = NSBezierPath()
            p.move(to: CGPoint(x: hipX, y: hipY))
            p.line(to: CGPoint(x: hipX + pawOff * W, y: groundY))
            p.lineWidth = legW; p.lineCapStyle = .round
            col.setStroke(); p.stroke()
        }

        // 身体
        let bodyRect = CGRect(x: W * 0.12, y: H * 0.30, width: W * 0.64, height: H * 0.38)
        body.setFill(); NSBezierPath(ovalIn: bodyRect).fill()

        // 头
        let hcx = W * 0.80, hcy = H * 0.60, hr = H * 0.21
        // 耳朵
        for (apexX, bx0, bx1) in [(W * 0.74, W * 0.70, W * 0.80), (W * 0.87, W * 0.83, W * 0.93)] {
            let ear = NSBezierPath()
            ear.move(to: CGPoint(x: bx0, y: hcy + hr * 0.55))
            ear.line(to: CGPoint(x: apexX, y: hcy + hr * 1.55))
            ear.line(to: CGPoint(x: bx1, y: hcy + hr * 0.55))
            ear.close()
            body.setFill(); ear.fill()
        }
        body.setFill()
        NSBezierPath(ovalIn: CGRect(x: hcx - hr, y: hcy - hr, width: hr * 2, height: hr * 2)).fill()
        // 口鼻
        let snout = NSBezierPath()
        snout.move(to: CGPoint(x: hcx + hr * 0.6, y: hcy + hr * 0.2))
        snout.line(to: CGPoint(x: hcx + hr * 1.5, y: hcy - hr * 0.1))
        snout.line(to: CGPoint(x: hcx + hr * 0.6, y: hcy - hr * 0.5))
        snout.close()
        body.setFill(); snout.fill()

        // 肚子暗部
        shade.withAlphaComponent(0.6).setFill()
        NSBezierPath(ovalIn: CGRect(x: W * 0.18, y: H * 0.30, width: W * 0.5, height: H * 0.16)).fill()

        // 黄眼睛
        eye.setFill()
        NSBezierPath(ovalIn: CGRect(x: hcx + hr * 0.25, y: hcy + hr * 0.05, width: W * 0.05, height: H * 0.10)).fill()
        dark.setFill()
        NSBezierPath(ovalIn: CGRect(x: hcx + hr * 0.42, y: hcy + hr * 0.05, width: W * 0.018, height: H * 0.10)).fill()
    }

    /// 毛线团 🧶。
    static func ball(side S: CGFloat) -> NSImage {
        render(width: S, height: S) {
            let r = S * 0.40
            let c = CGPoint(x: S * 0.5, y: S * 0.46)
            let circle = NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            NSColor(srgbRed: 0.96, green: 0.52, blue: 0.58, alpha: 1).setFill(); circle.fill()

            // 缠绕的毛线（裁剪在球内，两个方向交叉）
            NSGraphicsContext.saveGraphicsState()
            circle.addClip()
            NSColor(srgbRed: 0.83, green: 0.34, blue: 0.42, alpha: 0.85).setStroke()
            for off in stride(from: -2.0, through: 2.0, by: 1.0) {
                for ang in [35.0, -35.0] {
                    let p = NSBezierPath()
                    let rad = ang * .pi / 180
                    let dx = cos(rad), dy = sin(rad)
                    let mx = c.x + CGFloat(off) * r * 0.42 * CGFloat(-dy)
                    let my = c.y + CGFloat(off) * r * 0.42 * CGFloat(dx)
                    p.move(to: CGPoint(x: mx - CGFloat(dx) * r * 1.4, y: my - CGFloat(dy) * r * 1.4))
                    p.line(to: CGPoint(x: mx + CGFloat(dx) * r * 1.4, y: my + CGFloat(dy) * r * 1.4))
                    p.lineWidth = S * 0.03; p.stroke()
                }
            }
            NSGraphicsContext.restoreGraphicsState()

            // 球边 + 高光
            NSColor(srgbRed: 0.80, green: 0.32, blue: 0.40, alpha: 0.7).setStroke()
            circle.lineWidth = S * 0.012; circle.stroke()
            NSColor.white.withAlphaComponent(0.5).setFill()
            NSBezierPath(ovalIn: CGRect(x: c.x - r * 0.55, y: c.y + r * 0.25, width: r * 0.35, height: r * 0.35)).fill()

            // 垂下来的一缕线头
            let strand = NSBezierPath()
            strand.move(to: CGPoint(x: c.x + r * 0.7, y: c.y - r * 0.3))
            strand.curve(to: CGPoint(x: c.x + r * 1.15, y: c.y - r * 0.9),
                         controlPoint1: CGPoint(x: c.x + r * 1.1, y: c.y - r * 0.3),
                         controlPoint2: CGPoint(x: c.x + r * 0.8, y: c.y - r * 0.7))
            NSColor(srgbRed: 0.96, green: 0.52, blue: 0.58, alpha: 1).setStroke()
            strand.lineWidth = S * 0.025; strand.lineCapStyle = .round; strand.stroke()
        }
    }

    // MARK: - 绘制（坐标原点左下，单位 = 点）

    private static func draw(level: Int, mood: Double, overworked: Bool, S: CGFloat) {
        let fur = furColor(level: level)
        let dark = fur.blended(withFraction: 0.30, of: .black) ?? fur
        let light = fur.blended(withFraction: 0.62, of: .white) ?? fur
        let isDarkFur = fur.brightnessApprox < 0.45
        let ink = isDarkFur ? NSColor(white: 0.96, alpha: 1) : NSColor(srgbRed: 0.20, green: 0.16, blue: 0.16, alpha: 1)

        let cx = S * 0.5, cy = S * 0.45
        let hw = S * 0.345, hh = S * 0.315
        let exp = expression(mood: mood, overworked: overworked)

        // 等级 ≥7 戴皇冠（先画，被耳朵/头压住底部）
        if level >= 7 { drawCrown(cx: cx, y: cy + hh + S * 0.10, S: S) }

        // 耳朵
        drawEar(left: true, cx: cx, cy: cy, hw: hw, hh: hh, fur: fur, dark: dark, S: S)
        drawEar(left: false, cx: cx, cy: cy, hw: hw, hh: hh, fur: fur, dark: dark, S: S)

        // 头
        let head = NSBezierPath(ovalIn: CGRect(x: cx - hw, y: cy - hh, width: hw * 2, height: hh * 2))
        fur.setFill(); head.fill()
        dark.setStroke(); head.lineWidth = S * 0.018; head.stroke()

        // 嘴部浅色块（让五官在深色毛上也看得清）
        let muzzle = NSBezierPath(ovalIn: CGRect(x: cx - hw * 0.5, y: cy - hh * 0.78,
                                                 width: hw, height: hh * 0.8))
        light.withAlphaComponent(0.9).setFill(); muzzle.fill()

        // 腮红
        NSColor.systemPink.withAlphaComponent(0.32).setFill()
        for sgn in [-1.0, 1.0] {
            let r = S * 0.045
            NSBezierPath(ovalIn: CGRect(x: cx + CGFloat(sgn) * hw * 0.58 - r,
                                        y: cy - hh * 0.18 - r, width: r * 2, height: r * 2)).fill()
        }

        // 胡须
        ink.withAlphaComponent(0.55).setStroke()
        for sgn in [-1.0, 1.0] {
            for k in -1...1 {
                let p = NSBezierPath()
                let x0 = cx + CGFloat(sgn) * hw * 0.30
                let y0 = cy - hh * 0.10 + CGFloat(k) * S * 0.05
                p.move(to: CGPoint(x: x0, y: y0))
                p.line(to: CGPoint(x: cx + CGFloat(sgn) * hw * 0.95,
                                   y: y0 + CGFloat(k) * S * 0.03))
                p.lineWidth = S * 0.008; p.stroke()
            }
        }

        // 眼睛（猫王戴墨镜，跳过普通眼）
        let eyeY = cy + S * 0.045, eyeDX = S * 0.15
        if level >= 8 {
            drawSunglasses(cx: cx, eyeY: eyeY, eyeDX: eyeDX, S: S)
        } else {
            drawEyes(exp: exp, cx: cx, eyeY: eyeY, eyeDX: eyeDX, S: S, ink: ink)
        }

        // 鼻子
        let noseY = cy - hh * 0.10
        let nose = NSBezierPath()
        let nw = S * 0.035
        nose.move(to: CGPoint(x: cx - nw, y: noseY))
        nose.line(to: CGPoint(x: cx + nw, y: noseY))
        nose.line(to: CGPoint(x: cx, y: noseY - nw * 1.1))
        nose.close()
        NSColor(srgbRed: 0.92, green: 0.50, blue: 0.55, alpha: 1).setFill(); nose.fill()

        // 嘴
        drawMouth(exp: exp, cx: cx, topY: noseY - nw * 1.1, S: S, ink: ink)

        // 等级 ≥6 戴领结
        if level >= 6 { drawBowtie(cx: cx, y: cy - hh * 0.92, S: S) }
    }

    private static func drawEar(left: Bool, cx: CGFloat, cy: CGFloat, hw: CGFloat, hh: CGFloat,
                                fur: NSColor, dark: NSColor, S: CGFloat) {
        let sgn: CGFloat = left ? -1 : 1
        let base1 = CGPoint(x: cx + sgn * hw * 0.72, y: cy + hh * 0.55)
        let base2 = CGPoint(x: cx + sgn * hw * 0.10, y: cy + hh * 0.92)
        let apex  = CGPoint(x: cx + sgn * hw * 0.62, y: cy + hh * 1.28)
        let ear = NSBezierPath()
        ear.move(to: base1); ear.line(to: apex); ear.line(to: base2); ear.close()
        fur.setFill(); ear.fill()
        dark.setStroke(); ear.lineWidth = S * 0.015; ear.stroke()
        // 内耳
        let inner = NSBezierPath()
        inner.move(to: CGPoint(x: base1.x * 0.5 + apex.x * 0.5, y: base1.y * 0.45 + apex.y * 0.55))
        inner.line(to: CGPoint(x: apex.x * 0.7 + base2.x * 0.3, y: apex.y * 0.7 + base2.y * 0.3))
        inner.line(to: CGPoint(x: base2.x * 0.5 + base1.x * 0.5, y: base2.y * 0.5 + base1.y * 0.5))
        inner.close()
        NSColor.systemPink.withAlphaComponent(0.6).setFill(); inner.fill()
    }

    private static func drawEyes(exp: CatExpression, cx: CGFloat, eyeY: CGFloat, eyeDX: CGFloat,
                                 S: CGFloat, ink: NSColor) {
        for sgn in [-1.0, 1.0] {
            let ex = cx + CGFloat(sgn) * eyeDX
            switch exp {
            case .happy:
                // 弯弯笑眼 ∪
                ink.setStroke()
                let p = NSBezierPath()
                p.appendArc(withCenter: CGPoint(x: ex, y: eyeY + S * 0.01),
                            radius: S * 0.05, startAngle: 200, endAngle: 340, clockwise: false)
                p.lineWidth = S * 0.016; p.lineCapStyle = .round; p.stroke()
            case .content, .neutral:
                let r: CGFloat = exp == .content ? S * 0.052 : S * 0.046
                ink.setFill()
                NSBezierPath(ovalIn: CGRect(x: ex - r, y: eyeY - r, width: r * 2, height: r * 2)).fill()
                NSColor.white.setFill()
                let hr = r * 0.4
                NSBezierPath(ovalIn: CGRect(x: ex - hr * 0.2, y: eyeY + r * 0.3,
                                            width: hr, height: hr)).fill()
            case .sad:
                let r = S * 0.044
                ink.setFill()
                NSBezierPath(ovalIn: CGRect(x: ex - r, y: eyeY - r * 1.1, width: r * 2, height: r * 2)).fill()
                // 担忧眉：外低内高
                ink.setStroke()
                let b = NSBezierPath()
                b.move(to: CGPoint(x: ex - CGFloat(sgn) * S * 0.06, y: eyeY + S * 0.085))
                b.line(to: CGPoint(x: ex + CGFloat(sgn) * S * 0.03, y: eyeY + S * 0.055))
                b.lineWidth = S * 0.013; b.lineCapStyle = .round; b.stroke()
            case .angry:
                let r = S * 0.044
                ink.setFill()
                NSBezierPath(ovalIn: CGRect(x: ex - r, y: eyeY - r, width: r * 2, height: r * 2)).fill()
                // 怒眉：内低外高
                ink.setStroke()
                let b = NSBezierPath()
                b.move(to: CGPoint(x: ex - CGFloat(sgn) * S * 0.06, y: eyeY + S * 0.055))
                b.line(to: CGPoint(x: ex + CGFloat(sgn) * S * 0.04, y: eyeY + S * 0.085))
                b.lineWidth = S * 0.014; b.lineCapStyle = .round; b.stroke()
            }
        }
    }

    private static func drawMouth(exp: CatExpression, cx: CGFloat, topY: CGFloat, S: CGFloat, ink: NSColor) {
        ink.setStroke()
        let r = S * 0.045
        switch exp {
        case .happy:
            // 张嘴笑 + 粉舌头
            let smile = NSBezierPath()
            smile.appendArc(withCenter: CGPoint(x: cx, y: topY + S * 0.005),
                            radius: r * 1.5, startAngle: 200, endAngle: 340, clockwise: false)
            smile.lineWidth = S * 0.016; smile.lineCapStyle = .round; smile.stroke()
            NSColor(srgbRed: 0.95, green: 0.55, blue: 0.6, alpha: 1).setFill()
            NSBezierPath(ovalIn: CGRect(x: cx - r * 0.5, y: topY - r * 0.9,
                                        width: r, height: r * 0.8)).fill()
        case .content, .neutral:
            let p = NSBezierPath()
            p.move(to: CGPoint(x: cx, y: topY))
            p.line(to: CGPoint(x: cx, y: topY - S * 0.025))
            p.lineWidth = S * 0.013; p.lineCapStyle = .round; p.stroke()
            for sgn in [-1.0, 1.0] {
                let a = NSBezierPath()
                a.appendArc(withCenter: CGPoint(x: cx + CGFloat(sgn) * r, y: topY - S * 0.025),
                            radius: r, startAngle: 180, endAngle: 360, clockwise: false)
                a.lineWidth = S * 0.013; a.lineCapStyle = .round; a.stroke()
            }
        case .sad, .angry:
            let p = NSBezierPath()
            p.appendArc(withCenter: CGPoint(x: cx, y: topY - S * 0.05),
                        radius: r, startAngle: 20, endAngle: 160, clockwise: false)
            p.lineWidth = S * 0.014; p.lineCapStyle = .round; p.stroke()
        }
    }

    private static func drawCrown(cx: CGFloat, y: CGFloat, S: CGFloat) {
        let w = S * 0.22, h = S * 0.12
        let p = NSBezierPath()
        p.move(to: CGPoint(x: cx - w / 2, y: y))
        p.line(to: CGPoint(x: cx - w / 2, y: y + h * 0.4))
        p.line(to: CGPoint(x: cx - w * 0.28, y: y + h))
        p.line(to: CGPoint(x: cx - w * 0.14, y: y + h * 0.45))
        p.line(to: CGPoint(x: cx, y: y + h * 1.05))
        p.line(to: CGPoint(x: cx + w * 0.14, y: y + h * 0.45))
        p.line(to: CGPoint(x: cx + w * 0.28, y: y + h))
        p.line(to: CGPoint(x: cx + w / 2, y: y + h * 0.4))
        p.line(to: CGPoint(x: cx + w / 2, y: y))
        p.close()
        NSColor(srgbRed: 1.0, green: 0.82, blue: 0.2, alpha: 1).setFill(); p.fill()
        NSColor(srgbRed: 0.8, green: 0.6, blue: 0.0, alpha: 1).setStroke()
        p.lineWidth = S * 0.012; p.stroke()
    }

    private static func drawBowtie(cx: CGFloat, y: CGFloat, S: CGFloat) {
        let w = S * 0.085, h = S * 0.075
        let red = NSColor(srgbRed: 0.85, green: 0.22, blue: 0.25, alpha: 1)
        for sgn in [-1.0, 1.0] {
            let t = NSBezierPath()
            t.move(to: CGPoint(x: cx, y: y))
            t.line(to: CGPoint(x: cx + CGFloat(sgn) * w, y: y + h / 2))
            t.line(to: CGPoint(x: cx + CGFloat(sgn) * w, y: y - h / 2))
            t.close()
            red.setFill(); t.fill()
        }
        red.blended(withFraction: 0.3, of: .black)?.setFill()
        let knot = S * 0.022
        NSBezierPath(ovalIn: CGRect(x: cx - knot, y: y - knot, width: knot * 2, height: knot * 2)).fill()
    }

    private static func drawSunglasses(cx: CGFloat, eyeY: CGFloat, eyeDX: CGFloat, S: CGFloat) {
        NSColor(white: 0.08, alpha: 1).setFill()
        let w = S * 0.13, h = S * 0.10
        for sgn in [-1.0, 1.0] {
            let ex = cx + CGFloat(sgn) * eyeDX
            NSBezierPath(roundedRect: CGRect(x: ex - w / 2, y: eyeY - h / 2, width: w, height: h),
                         xRadius: S * 0.02, yRadius: S * 0.02).fill()
        }
        let bridge = NSBezierPath()
        bridge.move(to: CGPoint(x: cx - eyeDX + w / 2, y: eyeY))
        bridge.line(to: CGPoint(x: cx + eyeDX - w / 2, y: eyeY))
        bridge.lineWidth = S * 0.02; NSColor(white: 0.08, alpha: 1).setStroke(); bridge.stroke()
    }
}

extension NSColor {
    /// 粗略亮度（用于判断深/浅毛色）。
    var brightnessApprox: CGFloat {
        guard let c = usingColorSpace(.deviceRGB) else { return 0.5 }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
    }
}
