import SwiftUI

/// Reusable "it worked" flourish for buttons whose action gives no visible
/// result of its own (Copy Link, Create Invite Link, …).
///
/// Keep a counter in the view, increment it inside the button action, and
/// pass it as `trigger`: the control gives a quick spring pop and emits a
/// soft expanding ring in the accent color.
///
///     @State private var copied = 0
///     Button {
///       model.copyLatestInvite()
///       copied += 1
///     } label: {
///       ConfirmingLabel("Copy Link", systemImage: "doc.on.doc", trigger: copied)
///     }
///     .actionFeedback(trigger: copied)
extension View {
  func actionFeedback(trigger: Int) -> some View {
    modifier(ActionFeedbackModifier(trigger: trigger))
  }
}

private struct ActionFeedbackModifier: ViewModifier {
  var trigger: Int

  private struct Ring {
    var scale: CGFloat = 1
    var opacity: Double = 0
  }

  func body(content: Content) -> some View {
    content
      .keyframeAnimator(initialValue: CGFloat(1), trigger: trigger) { view, scale in
        view.scaleEffect(scale)
      } keyframes: { _ in
        CubicKeyframe(0.95, duration: 0.07)
        SpringKeyframe(1.04, duration: 0.16, spring: .bouncy)
        SpringKeyframe(1.0, duration: 0.22, spring: .smooth)
      }
      .overlay {
        Capsule()
          .stroke(Color.accentColor, lineWidth: 1.5)
          .keyframeAnimator(initialValue: Ring(), trigger: trigger) { view, ring in
            view
              .scaleEffect(ring.scale)
              .opacity(ring.opacity)
          } keyframes: { _ in
            KeyframeTrack(\.scale) {
              CubicKeyframe(1.0, duration: 0.05)
              CubicKeyframe(1.45, duration: 0.5)
            }
            KeyframeTrack(\.opacity) {
              CubicKeyframe(0.7, duration: 0.05)
              CubicKeyframe(0.0, duration: 0.5)
            }
          }
          .allowsHitTesting(false)
      }
  }
}

/// A `Label` whose icon briefly morphs into a checkmark each time `trigger`
/// increments. The title stays put so the button doesn't change width.
struct ConfirmingLabel: View {
  var title: String
  var systemImage: String
  var trigger: Int

  @State private var confirmed = false
  @State private var resetTask: Task<Void, Never>?

  init(_ title: String, systemImage: String, trigger: Int) {
    self.title = title
    self.systemImage = systemImage
    self.trigger = trigger
  }

  var body: some View {
    Label(title, systemImage: confirmed ? "checkmark" : systemImage)
      .contentTransition(.symbolEffect(.replace))
      .animation(.snappy(duration: 0.25), value: confirmed)
      .onChange(of: trigger) {
        confirmed = true
        resetTask?.cancel()
        resetTask = Task {
          try? await Task.sleep(for: .seconds(1.2))
          if !Task.isCancelled { confirmed = false }
        }
      }
      .onDisappear {
        resetTask?.cancel()
        confirmed = false
      }
  }
}
