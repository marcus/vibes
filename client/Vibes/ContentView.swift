import SwiftUI

struct ContentView: View {
  @State private var mode = "Broadcasting"
  @State private var status = "working on Vibes"

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Vibes")
          .font(.title2.weight(.semibold))
        Spacer()
        Picker("Mode", selection: $mode) {
          Text("Broadcasting").tag("Broadcasting")
          Text("Quiet").tag("Quiet")
          Text("Offline").tag("Offline")
        }
        .labelsHidden()
        .pickerStyle(.menu)
      }

      VStack(alignment: .leading, spacing: 10) {
        FriendRow(name: "Marcus", vibe: "vibing", detail: "+1.2k LOC", status: status)
        FriendRow(name: "Ken", vibe: "deep work", detail: "+412 LOC", status: "refactoring the weird part")
        FriendRow(name: "Justin", vibe: "quiet", detail: "-", status: "online, not broadcasting")
      }

      Divider()

      TextField("Status", text: $status)
        .textFieldStyle(.roundedBorder)

      HStack {
        Button("Scan Now") {}
        Spacer()
        Text("Relay: vibes.opentangle.com")
          .foregroundStyle(.secondary)
          .font(.caption)
      }
    }
    .padding(18)
    .frame(width: 380)
  }
}

private struct FriendRow: View {
  let name: String
  let vibe: String
  let detail: String
  let status: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text(name)
          .fontWeight(.medium)
        Text(vibe)
          .foregroundStyle(.secondary)
        Spacer()
        Text(detail)
          .foregroundStyle(.secondary)
          .monospacedDigit()
      }
      Text(status)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
  }
}

#Preview {
  ContentView()
}
