import AppKit
import ApplicationServices
import Metal
import MetalKit

/// The four candidates for Park's first-launch moment. Each is light drawn over the real screen,
/// ending on Park's menu bar icon, where the panel (and the guided tour) begins.
enum IntroEffect: String, CaseIterable, Identifiable {
    case ripple, dawn, clearing, lanes, gather, liquid, fireflies, tide, bloom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ripple: return "Ripple"
        case .dawn: return "Dawn"
        case .clearing: return "Clearing"
        case .lanes: return "Lanes"
        case .gather: return "Gather"
        case .liquid: return "Liquid"
        case .fireflies: return "Fireflies"
        case .tide: return "Tide"
        case .bloom: return "Bloom"
        }
    }

    /// What the effect is for, in one line.
    var intent: String {
        switch self {
        case .ripple: return "A ring of light spreads from Park’s icon: this is where Park lives."
        case .dawn: return "Morning light pours down from the menu bar, like the website."
        case .clearing: return "A frosted veil gathers into Park: the gesture of putting things away."
        case .lanes: return "Painted lines settle into a parking bay where the panel opens."
        case .gather: return "Soft rings of light draw in from the edges and close around Park’s icon."
        case .liquid: return "A pool of blue light flows across the screen and pours into the icon."
        case .fireflies: return "Hundreds of tiny lights drift, then gather into a ring around the icon."
        case .tide: return "A soft wave rolls in from every edge and closes in on Park."
        case .bloom: return "Watercolor blooms spread, then draw back into Park, as if inhaled."
        }
    }

    var duration: Double {
        switch self {
        case .ripple: return 2.9
        case .dawn: return 2.9
        case .clearing: return 3.0
        case .lanes, .gather, .liquid, .fireflies, .tide, .bloom: return 3.0
        }
    }

    var fragmentName: String { "\(rawValue)Fragment" }
}

struct IntroUniforms {
    var time: Float
    var fadeOut: Float
    var resolution: SIMD2<Float>
    var origin: SIMD2<Float>
    var scale: Float
    var duration: Float
}

/// Compiles the shaders once and draws any effect, on screen or offscreen.
final class IntroRenderer {
    let device: MTLDevice
    let queue: MTLCommandQueue
    private var pipelines: [IntroEffect: MTLRenderPipelineState] = [:]
    private var motes: MTLRenderPipelineState?
    static let moteCount = 320

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        guard let device, let queue = device.makeCommandQueue() else { return nil }
        let library: MTLLibrary
        do { library = try device.makeLibrary(source: IntroShaders.source, options: nil) } catch {
            Log.write("intro effects failed to compile: \(error)")
            print("shader error: \(error)")
            return nil
        }
        for effect in IntroEffect.allCases {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "fxVertex")
            descriptor.fragmentFunction = library.makeFunction(name: effect.fragmentName)
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            do { pipelines[effect] = try device.makeRenderPipelineState(descriptor: descriptor) } catch {
                print("pipeline error for \(effect): \(error)")
                return nil
            }
        }
        // Fireflies' motes: instanced soft sprites, blended over the screen-wide layer.
        let moteDescriptor = MTLRenderPipelineDescriptor()
        moteDescriptor.vertexFunction = library.makeFunction(name: "moteVertex")
        moteDescriptor.fragmentFunction = library.makeFunction(name: "moteFragment")
        let attachment = moteDescriptor.colorAttachments[0]!
        attachment.pixelFormat = .bgra8Unorm
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        motes = try? device.makeRenderPipelineState(descriptor: moteDescriptor)
        self.device = device
        self.queue = queue
    }

    func encode(_ effect: IntroEffect, into pass: MTLRenderPassDescriptor, buffer: MTLCommandBuffer, uniforms: IntroUniforms) {
        guard let pipeline = pipelines[effect] else { return }
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        var u = uniforms
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&u, length: MemoryLayout<IntroUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        if effect == .fireflies, let motes {
            encoder.setRenderPipelineState(motes)
            encoder.setVertexBytes(&u, length: MemoryLayout<IntroUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: Self.moteCount)
        }
        encoder.endEncoding()
    }

    /// One frame drawn offscreen, for design review. `size` and `origin` are in pixels.
    func frame(_ effect: IntroEffect, at time: Double, size: CGSize, origin: CGPoint, scale: CGFloat) -> CGImage? {
        let width = Int(size.width), height = Int(size.height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .managed
        guard let texture = device.makeTexture(descriptor: descriptor), let buffer = queue.makeCommandBuffer() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].storeAction = .store
        encode(effect, into: pass, buffer: buffer, uniforms: IntroUniforms(
            time: Float(time), fadeOut: 0, resolution: SIMD2(Float(size.width), Float(size.height)),
            origin: SIMD2(Float(origin.x), Float(origin.y)), scale: Float(scale), duration: Float(effect.duration)))
        if let blit = buffer.makeBlitCommandEncoder() { blit.synchronize(resource: texture); blit.endEncoding() }
        buffer.commit()
        buffer.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

/// Where Park's menu bar icon is, in global top-left points (the coordinates Accessibility uses).
enum IntroAnchor {
    enum Source: Equatable { case parkIcon, nearClock }

    /// Park's own status item if it's on screen; otherwise a point near the clock.
    static func locate(prefer: Source = .parkIcon) -> (point: CGPoint, source: Source) {
        if prefer == .parkIcon, let point = runningParkIcon() { return (point, .parkIcon) }
        return (nearClock(), .nearClock)
    }

    /// Asks the running copy of Park, through Accessibility, where its menu bar item is. Returns nil when
    /// Park isn't running or its icon is hidden (a full menu bar pushes icons behind the camera notch).
    static func runningParkIcon() -> CGPoint? {
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spencereverett.park")
            .filter { $0.processIdentifier != me && !$0.isTerminated }
        for app in others {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            var barValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &barValue) == .success,
                  let bar = barValue, CFGetTypeID(bar) == AXUIElementGetTypeID() else { continue }
            var childrenValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &childrenValue) == .success,
                  let item = (childrenValue as? [AXUIElement])?.first else { continue }
            var positionValue: CFTypeRef?, sizeValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue) == .success,
                  AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeValue) == .success else { continue }
            var position = CGPoint.zero, size = CGSize.zero
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            let center = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
            // An item parked behind the notch reports a position, but you can't see it there.
            if let screen = NSScreen.main, isHiddenByNotch(center, on: screen) { return nil }
            return center
        }
        return nil
    }

    /// A spot in the menu bar a little left of the clock, where a newly added icon usually lands.
    static func nearClock(on screen: NSScreen? = NSScreen.main) -> CGPoint {
        guard let screen else { return CGPoint(x: 1200, y: 12) }
        let menuBar = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        return CGPoint(x: screen.frame.minX + screen.frame.width - 210, y: menuBar / 2)
    }

    private static func isHiddenByNotch(_ point: CGPoint, on screen: NSScreen) -> Bool {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return false }
        // The notch is the gap between the two usable top areas (AppKit x matches top-left x on the main screen).
        return point.x > left.maxX && point.x < right.minX
    }
}

/// Plays one effect over the whole main screen, click-through and above everything, skippable with any
/// click or key. Never plays with Reduce Motion on.
@MainActor
final class IntroEffectPlayer: NSObject, MTKViewDelegate {
    private var window: NSWindow?
    private var renderer: IntroRenderer?
    private var effect: IntroEffect = .ripple
    private var speed: Double = 1
    private var origin: CGPoint = .zero   // global top-left points
    private var start = CACurrentMediaTime()
    private var skippedAt: CFTimeInterval?
    private var monitors: [Any] = []
    private var done: () -> Void = {}

    var isPlaying: Bool { window != nil }

    /// - Parameters:
    ///   - origin: Park's icon in global top-left points (see `IntroAnchor`).
    ///   - speed: 1 for real time, 0.5 to study the motion.
    func play(_ effect: IntroEffect, origin: CGPoint, speed: Double = 1, respectReduceMotion: Bool = true,
              done: @escaping () -> Void = {}) {
        stop()
        guard let screen = NSScreen.main, let renderer = renderer ?? IntroRenderer(),
              !(respectReduceMotion && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) else {
            done(); return
        }
        self.renderer = renderer
        self.effect = effect
        self.speed = speed
        self.origin = origin
        self.done = done
        skippedAt = nil

        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        // Above the menu bar, so the light can reach Park's icon.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.setFrame(screen.frame, display: false)

        let view = MTKView(frame: CGRect(origin: .zero, size: screen.frame.size), device: renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.preferredFramesPerSecond = 120
        view.layer?.isOpaque = false
        view.delegate = self
        window.contentView = view
        window.orderFrontRegardless()
        self.window = window
        start = CACurrentMediaTime()

        let skip: (NSEvent) -> Void = { [weak self] _ in self?.skip() }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: skip) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] e in self?.skip(); return e }) { monitors.append(m) }
    }

    func skip() {
        guard isPlaying, skippedAt == nil else { return }
        skippedAt = CACurrentMediaTime()
    }

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { render(view) }
    }

    private func render(_ view: MTKView) {
        guard let renderer, let window, let screen = window.screen ?? NSScreen.main,
              let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = renderer.queue.makeCommandBuffer() else { return }
        let now = CACurrentMediaTime()
        let t = (now - start) * speed
        let fade = skippedAt.map { min(1, (now - $0) / 0.25) } ?? 0
        if t >= effect.duration || fade >= 1 { finish(); return }

        let size = view.drawableSize
        let scale = size.width / max(1, screen.frame.width)
        let originPx = CGPoint(x: (origin.x - screen.frame.minX) * scale, y: origin.y * scale)
        renderer.encode(effect, into: pass, buffer: buffer, uniforms: IntroUniforms(
            time: Float(t), fadeOut: Float(fade), resolution: SIMD2(Float(size.width), Float(size.height)),
            origin: SIMD2(Float(originPx.x), Float(originPx.y)), scale: Float(scale), duration: Float(effect.duration)))
        buffer.present(drawable)
        buffer.commit()
    }

    private func finish() {
        let callback = done
        stop()
        callback()
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        (window?.contentView as? MTKView)?.isPaused = true
        window?.orderOut(nil)
        window = nil
        done = {}
    }
}
