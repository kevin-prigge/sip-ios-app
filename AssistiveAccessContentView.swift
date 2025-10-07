import SwiftUI

struct AssistiveAccessContentView: View {
    @StateObject private var settings = SettingsStore()
    @State private var todayML: Double = 0
    @State private var didAdd: Bool = false

    private var defaultAmountML: Double {
        // Default to ~12 oz in current unit
        12 * 29.574
    }

    private var progress: Double {
        let adjustedGoal = settings.goalML
        return adjustedGoal > 0 ? min(todayML / adjustedGoal, 1.0) : 0
    }

    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 16) {
                Text("Water Today")
                    .font(.system(size: 48, weight: .bold))
                Text("\(Int(todayML)) mL of \(Int(settings.goalML)) mL")
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 60)

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.blue)
                .frame(height: 20)
                .padding(.horizontal, 40)
                .accessibilityLabel("Progress toward daily water goal")

            Button {
                didAdd.toggle()
                Task {
                    try? await HealthKitManager.shared.addWater(mL: defaultAmountML)
                    await refresh()
                }
            } label: {
                Label("Add 12 oz Water", systemImage: "drop.fill")
                    .font(.system(size: 36, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.glassProminent)
            .sensoryFeedback(.success, trigger: didAdd)
            .padding(.horizontal, 40)

            Spacer()
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 0))
        .task { await refresh() }
        .padding(.bottom, 60)
    }

    @MainActor
    private func refresh() async {
        let ml = (try? await HealthKitManager.shared.todayTotalML()) ?? 0
        todayML = ml
    }
}

#Preview {
    AssistiveAccessContentView()
}
