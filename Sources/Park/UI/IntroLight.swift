import AppKit
import Metal
import MetalKit

/// The first-launch moment: soft shafts of dawn-blue light pour down from the menu bar, where Park
/// lives, then recede as the walkthrough arrives. About two and a half seconds,
/// skippable with any click or key, and never shown with Reduce Motion on.
///
/// The shader is compiled from source at runtime, so building Park needs no Metal toolchain.
enum IntroLight {
    static let duration: Double = 2.8
    /// When the walkthrough window starts to arrive, as the light peaks.
    static let handoff: Double = 1.55

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms { float time; float fadeOut; float2 resolution; float2 origin; };
    struct VOut { float4 position [[position]]; };

    // One triangle that covers the screen.
    vertex VOut introVertex(uint id [[vertex_id]]) {
        float2 p = float2((id << 1) & 2, id & 2);
        VOut out; out.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return out;
    }

    static float hash(float2 p) { return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453); }

    // Smooth 1D noise around the circle, so beams vary in width and brightness without looking regular.
    static float angularNoise(float a, float freq, float seed) {
        float x = a * freq + seed;
        float i = floor(x), f = fract(x);
        float u = f * f * (3.0 - 2.0 * f);
        return mix(hash(float2(i, seed)), hash(float2(i + 1.0, seed)), u);
    }

    fragment float4 introFragment(VOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
        float t = u.time;
        float2 uv = (in.position.xy - u.origin) / u.resolution.y;
        float r = length(uv);
        float a = atan2(uv.y, uv.x);
        // Wrap-safe angle for the noise (period 2π maps onto integer cells).
        float an = (a + M_PI_F) / (2.0 * M_PI_F) * 14.0;

        // Shafts: broad, soft angular noise that drifts slowly, like light through haze.
        float beams = 0.0;
        beams += pow(angularNoise(an, 1.0, 3.1 + t * 0.09), 3.5) * 0.55;
        beams += pow(angularNoise(an, 2.0, 7.7 - t * 0.07), 4.0) * 0.55;
        beams += pow(angularNoise(an, 3.0, 1.3 + t * 0.12), 6.0) * 0.35;

        // The light pours down from above and reaches further as it blooms.
        float reach = mix(0.35, 1.9, smoothstep(0.0, 1.6, t));
        float extent = 1.0 - smoothstep(reach * 0.45, reach, r);
        float shafts = beams * extent * (0.45 + 0.55 * exp(-r * 0.8));
        float wash = exp(-r * 2.4) * 0.7;
        float light = shafts * 1.35 + wash;

        // Envelope: rise, hold briefly, recede; a skip fades everything out quickly.
        float env = smoothstep(0.0, 0.7, t) * (1.0 - smoothstep(1.9, 2.8, t)) * (1.0 - u.fadeOut);
        light *= env;

        // Dawn ramp: navy → sign blue → sky → first light, by intensity.
        float3 navy = float3(0.043, 0.106, 0.212);
        float3 sign = float3(0.118, 0.314, 0.659);
        float3 sky  = float3(0.612, 0.753, 0.918);
        float3 first = float3(0.890, 0.933, 0.980);
        float3 color = mix(navy, sign, smoothstep(0.0, 0.35, light));
        color = mix(color, sky, smoothstep(0.3, 0.75, light));
        color = mix(color, first, smoothstep(0.7, 1.15, light));

        // A gentle navy veil over the whole screen, deepest at the edges, so the light reads.
        float veil = 0.42 * env * (0.55 + 0.45 * smoothstep(0.4, 1.4, r));

        float glow = clamp(light, 0.0, 1.0);
        float alpha = clamp(veil + glow * (1.0 - veil), 0.0, 1.0);
        float3 rgb = navy * veil * (1.0 - glow) + color * glow;

        // Fine grain keeps the gradients from banding.
        float grain = (hash(in.position.xy + fract(t) * 91.7) - 0.5) * 0.035 * env;
        rgb = clamp(rgb + grain, 0.0, 1.0);
        return float4(rgb, alpha);  // premultiplied
    }
    """

    struct Uniforms {
        var time: Float
        var fadeOut: Float
        var resolution: SIMD2<Float>
        var origin: SIMD2<Float>
    }

    /// Compiles the shader once per device.
    final class Renderer {
        let device: MTLDevice
        let pipeline: MTLRenderPipelineState
        let queue: MTLCommandQueue

        init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
            guard let device, let queue = device.makeCommandQueue() else { return nil }
            let library: MTLLibrary
            do { library = try device.makeLibrary(source: IntroLight.shaderSource, options: nil) } catch {
                Log.write("intro light shader failed to compile: \(error)")
                print("shader error: \(error)")
                return nil
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "introVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "introFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
            self.device = device; self.queue = queue; self.pipeline = pipeline
        }

        func encode(into pass: MTLRenderPassDescriptor, buffer: MTLCommandBuffer, uniforms: Uniforms) {
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
            var u = uniforms
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }

        /// Draws one frame offscreen (for design review) and returns it as an image.
        func frame(at time: Double, size: CGSize) -> CGImage? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Int(size.width),
                                                                      height: Int(size.height), mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .managed
            guard let texture = device.makeTexture(descriptor: descriptor), let buffer = queue.makeCommandBuffer() else { return nil }
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].storeAction = .store
            encode(into: pass, buffer: buffer, uniforms: Uniforms(
                time: Float(time), fadeOut: 0,
                resolution: SIMD2(Float(size.width), Float(size.height)),
                origin: SIMD2(Float(size.width / 2), Float(-size.height * 0.12))))
            if let blit = buffer.makeBlitCommandEncoder() { blit.synchronize(resource: texture); blit.endEncoding() }
            buffer.commit(); buffer.waitUntilCompleted()
            let width = Int(size.width), height = Int(size.height)
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
            let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
            return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                           space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider,
                           decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
    }

    // MARK: - On screen

    /// Plays the light over the main screen, calling `handoff` when the walkthrough should start to
    /// appear and `done` when the light has gone.
    @MainActor
    final class Player: NSObject, MTKViewDelegate {
        private var window: NSWindow?
        private var renderer: Renderer?
        private var start = CACurrentMediaTime()
        private var skippedAt: CFTimeInterval?
        private var handedOff = false
        private var monitors: [Any] = []
        private var handoff: () -> Void = {}
        private var done: () -> Void = {}
        /// Where the light comes from, in screen points (AppKit coordinates). nil: top centre.
        private var origin: CGPoint?
        private var screenFrame: CGRect = .zero

        func play(from origin: CGPoint? = nil, handoff: @escaping () -> Void, done: @escaping () -> Void = {}) {
            self.origin = origin
            guard let screen = NSScreen.main, let renderer = Renderer(),
                  !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                handoff(); done(); return
            }
            self.renderer = renderer
            self.screenFrame = screen.frame
            self.handoff = handoff
            self.done = done

            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

            let view = MTKView(frame: CGRect(origin: .zero, size: screen.frame.size), device: renderer.device)
            view.colorPixelFormat = .bgra8Unorm
            view.framebufferOnly = true
            view.layer?.isOpaque = false
            view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            view.preferredFramesPerSecond = 60
            view.delegate = self
            window.contentView = view
            window.orderFrontRegardless()
            self.window = window
            start = CACurrentMediaTime()

            // Any click or key skips ahead. The window ignores the mouse, so watch globally too.
            let skip: (NSEvent) -> Void = { [weak self] _ in self?.skip() }
            if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: skip) { monitors.append(m) }
            if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] e in self?.skip(); return e }) { monitors.append(m) }
        }

        private func skip() {
            guard skippedAt == nil else { return }
            skippedAt = CACurrentMediaTime()
            handOffIfNeeded()
        }

        private func handOffIfNeeded() {
            guard !handedOff else { return }
            handedOff = true
            handoff()
        }

        nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        nonisolated func draw(in view: MTKView) {
            MainActor.assumeIsolated { render(view) }
        }

        private func render(_ view: MTKView) {
            guard let renderer, let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
                  let buffer = renderer.queue.makeCommandBuffer() else { return }
            let now = CACurrentMediaTime()
            let t = now - start
            let fade = skippedAt.map { min(1, (now - $0) / 0.25) } ?? 0
            if t >= IntroLight.handoff { handOffIfNeeded() }
            if t >= IntroLight.duration || fade >= 1 { finish(); return }

            let size = view.drawableSize
            // The light pours down from just above the menu bar: from Park's icon when we know where it is.
            var source = SIMD2(Float(size.width / 2), Float(-size.height * 0.12))
            if let origin, screenFrame.width > 0 {
                let scale = size.width / screenFrame.width
                source = SIMD2(Float((origin.x - screenFrame.minX) * scale), Float(-size.height * 0.05))
            }
            let uniforms = Uniforms(time: Float(t), fadeOut: Float(fade),
                                    resolution: SIMD2(Float(size.width), Float(size.height)),
                                    origin: source)
            renderer.encode(into: pass, buffer: buffer, uniforms: uniforms)
            buffer.present(drawable)
            buffer.commit()
        }

        private func finish() {
            monitors.forEach(NSEvent.removeMonitor)
            monitors.removeAll()
            (window?.contentView as? MTKView)?.isPaused = true
            window?.orderOut(nil)
            window = nil
            renderer = nil
            done()
        }
    }
}
