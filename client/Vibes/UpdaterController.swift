import Combine
import Sparkle
import SwiftUI

/// Observes Sparkle's `canCheckForUpdates` so SwiftUI can enable/disable the
/// "Check for Updates..." item reactively. SwiftUI does not observe the raw KVO
/// property directly, so this view model bridges it to a published value.
final class CheckForUpdatesViewModel: ObservableObject {
  @Published var canCheckForUpdates = false

  init(updater: SPUUpdater) {
    updater.publisher(for: \.canCheckForUpdates)
      .assign(to: &$canCheckForUpdates)
  }
}

/// A `Check for Updates...` menu item backed by Sparkle. Reusable in both the
/// app command menu and the menu bar so the disabled state stays correct.
struct CheckForUpdatesView: View {
  @ObservedObject private var viewModel: CheckForUpdatesViewModel
  private let updater: SPUUpdater

  init(updater: SPUUpdater) {
    self.updater = updater
    self.viewModel = CheckForUpdatesViewModel(updater: updater)
  }

  var body: some View {
    Button("Check for Updates...", action: updater.checkForUpdates)
      .disabled(!viewModel.canCheckForUpdates)
  }
}
