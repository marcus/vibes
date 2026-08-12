import AppKit
import QuartzCore
import SwiftUI

// Core Animation helpers for ambient orbit motion.
// Moves layers on the render server instead of rebuilding the SwiftUI sky on a
// TimelineView / forever-animation clock.
//
// Sheen rotation uses a baked CALayer under a non-rotating circular mask —
// rotating an NSHostingView escapes SwiftUI clipShape and showed square corners.

extension View {
  /// Vertical ease-in-out bob via Core Animation.
  func ambientBob(
    enabled: Bool,
    period: TimeInterval,
    amplitude: CGFloat,
    phase: TimeInterval
  ) -> some View {
    AmbientBobHost(
      enabled: enabled,
      period: period,
      amplitude: amplitude,
      phase: phase,
      content: self
    )
  }

  /// Opacity breath via Core Animation.
  func ambientOpacityBreath(
    enabled: Bool,
    period: TimeInterval,
    from: Float,
    to: Float
  ) -> some View {
    AmbientOpacityHost(
      enabled: enabled,
      period: period,
      from: from,
      to: to,
      content: self
    )
  }
}

// MARK: - Sheen disk

/// Spectrum sheen: rasterized once, CA-rotated inside a circular mask.
struct AmbientSheenDisk: NSViewRepresentable {
  var isDark: Bool
  var enabled: Bool
  var period: TimeInterval
  var startDegrees: Double

  func makeNSView(context: Context) -> SheenDiskView {
    let view = SheenDiskView()
    view.apply(
      isDark: isDark,
      enabled: enabled,
      period: period,
      startDegrees: startDegrees
    )
    return view
  }

  func updateNSView(_ nsView: SheenDiskView, context: Context) {
    nsView.apply(
      isDark: isDark,
      enabled: enabled,
      period: period,
      startDegrees: startDegrees
    )
  }
}

final class SheenDiskView: NSView {
  private let imageLayer = CALayer()
  private var isDark = true
  private var enabled = false
  private var period: TimeInterval = 30
  private var startDegrees: Double = 210
  private var bakedIsDark: Bool?
  private var bakedSide: CGFloat = 0
  private var animationSignature = ""

  private static let rotationKey = "vibes.sheenRotation"

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = true
    imageLayer.contentsGravity = .resize
    imageLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
    layer?.addSublayer(imageLayer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(isDark: Bool, enabled: Bool, period: TimeInterval, startDegrees: Double) {
    self.isDark = isDark
    self.enabled = enabled
    self.period = period
    self.startDegrees = startDegrees
    needsLayout = true
    syncRotation()
  }

  override func layout() {
    super.layout()
    let side = min(bounds.width, bounds.height)
    guard side > 1 else { return }

    layer?.cornerRadius = side / 2
    layer?.masksToBounds = true

    // Oversized so a 45° turn still covers the circle.
    let cover = side * CGFloat(2).squareRoot() * 1.05
    imageLayer.bounds = CGRect(x: 0, y: 0, width: cover, height: cover)
    imageLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)

    if bakedIsDark != isDark || abs(bakedSide - cover) > 0.5 {
      bakeSheen(side: cover)
    }
    syncRotation()
  }

  private func bakeSheen(side: CGFloat) {
    let content = SheenBakeView(isDark: isDark)
      .frame(width: side, height: side)
    let renderer = ImageRenderer(content: content)
    renderer.scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    imageLayer.contents = renderer.cgImage
    bakedIsDark = isDark
    bakedSide = side
  }

  private func syncRotation() {
    let startRadians = startDegrees * .pi / 180
    let signature = String(format: "%.3f-%.2f-%d", period, startDegrees, enabled ? 1 : 0)

    if !enabled {
      imageLayer.removeAnimation(forKey: Self.rotationKey)
      imageLayer.transform = CATransform3DMakeRotation(CGFloat(startRadians), 0, 0, 1)
      animationSignature = signature
      return
    }

    if animationSignature == signature, imageLayer.animation(forKey: Self.rotationKey) != nil {
      return
    }
    animationSignature = signature
    imageLayer.removeAnimation(forKey: Self.rotationKey)

    let anim = CABasicAnimation(keyPath: "transform.rotation.z")
    anim.fromValue = startRadians
    anim.toValue = startRadians + (2 * Double.pi)
    anim.duration = max(period, 0.1)
    anim.repeatCount = .infinity
    anim.timingFunction = CAMediaTimingFunction(name: .linear)
    anim.isRemovedOnCompletion = false
    anim.fillMode = .forwards
    imageLayer.add(anim, forKey: Self.rotationKey)
  }
}

private struct SheenBakeView: View {
  var isDark: Bool

  private static let darkPalette: [Color] = [
    Color(red: 0.95, green: 0.27, blue: 0.23),
    Color(red: 0.98, green: 0.49, blue: 0.16),
    Color(red: 0.98, green: 0.78, blue: 0.24),
    Color(red: 0.22, green: 0.56, blue: 0.97),
    Color(red: 0.40, green: 0.33, blue: 0.93),
    Color(red: 0.66, green: 0.31, blue: 0.92),
    Color(red: 0.96, green: 0.36, blue: 0.66),
  ]
  private static let lightPalette: [Color] = [
    Color(red: 1.00, green: 0.55, blue: 0.50),
    Color(red: 1.00, green: 0.70, blue: 0.42),
    Color(red: 1.00, green: 0.88, blue: 0.48),
    Color(red: 0.42, green: 0.74, blue: 1.00),
    Color(red: 0.58, green: 0.64, blue: 1.00),
    Color(red: 0.76, green: 0.60, blue: 1.00),
    Color(red: 1.00, green: 0.62, blue: 0.78),
  ]

  var body: some View {
    let palette = isDark ? Self.darkPalette : Self.lightPalette
    AngularGradient(
      gradient: Gradient(colors: palette + [palette[0]]),
      center: .center,
      angle: .degrees(0)
    )
    .opacity(isDark ? 0.55 : 0.64)
    .blur(radius: 9)
  }
}

// MARK: - Bob

private struct AmbientBobHost<Content: View>: NSViewRepresentable {
  var enabled: Bool
  var period: TimeInterval
  var amplitude: CGFloat
  var phase: TimeInterval
  var content: Content

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> MeasuringContainer {
    let container = MeasuringContainer()
    container.wantsLayer = true
    let hosting = NSHostingView(rootView: content)
    hosting.wantsLayer = true
    hosting.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(hosting)
    NSLayoutConstraint.activate([
      hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      hosting.topAnchor.constraint(equalTo: container.topAnchor),
      hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    context.coordinator.hosting = hosting
    container.measure = { [weak hosting] in
      hosting?.fittingSize ?? .zero
    }
    return container
  }

  func updateNSView(_ nsView: MeasuringContainer, context: Context) {
    guard let hosting = context.coordinator.hosting else { return }
    hosting.rootView = content
    let fitted = hosting.fittingSize
    if fitted != context.coordinator.lastFittingSize {
      context.coordinator.lastFittingSize = fitted
      nsView.invalidateIntrinsicContentSize()
    }
    syncBob(on: hosting, coordinator: context.coordinator)
  }

  private func syncBob(on hosting: NSHostingView<Content>, coordinator: Coordinator) {
    hosting.wantsLayer = true
    guard let layer = hosting.layer else { return }
    let key = "vibes.ambientBob"
    let signature = String(format: "%.3f-%.2f-%.3f-%d", period, amplitude, phase, enabled ? 1 : 0)
    if !enabled {
      layer.removeAnimation(forKey: key)
      layer.transform = CATransform3DIdentity
      coordinator.animationSignature = signature
      return
    }
    // Re-arm if NSHostingView dropped the animation after a rootView update.
    if coordinator.animationSignature == signature, layer.animation(forKey: key) != nil {
      return
    }
    coordinator.animationSignature = signature
    layer.removeAnimation(forKey: key)

    let anim = CABasicAnimation(keyPath: "transform.translation.y")
    anim.fromValue = -amplitude
    anim.toValue = amplitude
    anim.duration = max(period / 2, 0.1)
    anim.autoreverses = true
    anim.repeatCount = .infinity
    anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    anim.beginTime = CACurrentMediaTime() - phase
    anim.isRemovedOnCompletion = false
    anim.fillMode = .forwards
    layer.add(anim, forKey: key)
  }

  final class Coordinator {
    var hosting: NSHostingView<Content>?
    var animationSignature = ""
    var lastFittingSize: NSSize = .zero
  }
}

// MARK: - Opacity breath

private struct AmbientOpacityHost<Content: View>: NSViewRepresentable {
  var enabled: Bool
  var period: TimeInterval
  var from: Float
  var to: Float
  var content: Content

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> MeasuringContainer {
    let container = MeasuringContainer()
    container.wantsLayer = true
    let hosting = NSHostingView(rootView: content)
    hosting.wantsLayer = true
    hosting.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(hosting)
    NSLayoutConstraint.activate([
      hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      hosting.topAnchor.constraint(equalTo: container.topAnchor),
      hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    context.coordinator.hosting = hosting
    container.measure = { [weak hosting] in
      hosting?.fittingSize ?? .zero
    }
    return container
  }

  func updateNSView(_ nsView: MeasuringContainer, context: Context) {
    guard let hosting = context.coordinator.hosting else { return }
    hosting.rootView = content
    let fitted = hosting.fittingSize
    if fitted != context.coordinator.lastFittingSize {
      context.coordinator.lastFittingSize = fitted
      nsView.invalidateIntrinsicContentSize()
    }
    syncOpacity(on: hosting, coordinator: context.coordinator)
  }

  private func syncOpacity(on hosting: NSHostingView<Content>, coordinator: Coordinator) {
    hosting.wantsLayer = true
    guard let layer = hosting.layer else { return }
    let key = "vibes.ambientOpacity"
    let signature = String(format: "%.3f-%.3f-%.3f-%d", period, from, to, enabled ? 1 : 0)
    if !enabled {
      layer.removeAnimation(forKey: key)
      layer.opacity = 1
      coordinator.animationSignature = signature
      return
    }
    if coordinator.animationSignature == signature, layer.animation(forKey: key) != nil {
      return
    }
    coordinator.animationSignature = signature
    layer.removeAnimation(forKey: key)

    let anim = CABasicAnimation(keyPath: "opacity")
    anim.fromValue = from
    anim.toValue = to
    anim.duration = max(period / 2, 0.1)
    anim.autoreverses = true
    anim.repeatCount = .infinity
    anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    anim.isRemovedOnCompletion = false
    anim.fillMode = .forwards
    layer.add(anim, forKey: key)
  }

  final class Coordinator {
    var hosting: NSHostingView<Content>?
    var animationSignature = ""
    var lastFittingSize: NSSize = .zero
  }
}

// MARK: - Shared container

final class MeasuringContainer: NSView {
  var measure: (() -> NSSize)?

  override var intrinsicContentSize: NSSize {
    let size = measure?() ?? .zero
    return size == .zero ? super.intrinsicContentSize : size
  }
}
