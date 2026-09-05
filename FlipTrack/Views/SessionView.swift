import SwiftUI
import SwiftData

struct SessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var configStore: ConfigStore
    @StateObject private var scanner = Scanner()
    @State private var showingPrefs = false
    let session: Session

    func formattedNumber(_ number: Int) -> String {
        number.formatted(.number.grouping(.automatic).locale(Locale(identifier: "de_DE")))
    }

    func color(for playerIndex: Int) -> Color { [Color.color1, Color.color2][playerIndex] }
    func winningColor(_ game: Game) -> Color { game.winningIndex == -1 ? .clear : color(for: game.winningIndex) }

    var body: some View {
        VStack(spacing: 0) {
            CurrentGameView(firstPlayer: session.firstPlayer,
                            secondPlayer: session.secondPlayer,
                            firstPlayerIndex: session.firstPlayerIndex,
                            colorFor: color(for:))
            TotalsView(playerTotals: session.playerTotals,
                       playerWins: session.playerWins,
                       highScores: session.highScores,
                       averageScores: session.averageScores,
                       colorFor: color(for:), formattedNumber: formattedNumber)
            if session.games?.isEmpty == false {
                GamesPlayedView(games: session.games ?? [], formattedNumber: formattedNumber,
                                winningColor: winningColor, colorFor: color(for:))
                    .disabled(scanner.isMonitoring)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal)
        .safeAreaInset(edge: .bottom) { monitorControls }
        .preferredColorScheme(.dark)
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gear") {
                    scanner.stop()
                    showingPrefs = true
                }
            }
        }
        .onDisappear { scanner.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { scanner.stop() }
        }
        .sheet(isPresented: $showingPrefs) { PreferencesView() }
    }

    private var monitorControls: some View {
        HStack(spacing: 12) {
            if scanner.isMonitoring {
                CameraPreview(session: scanner.camera.session)
                    .frame(width: 100, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("Live camera preview")
            }
            VStack(spacing: 10) {
                Text(scanner.error ?? scanner.status)
                    .font(.callout)
                    .foregroundStyle(scanner.error == nil ? Color.secondary : .red)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.updatesFrequently)
                CameraButton(monitoring: scanner.isMonitoring) {
                    if scanner.isMonitoring {
                        scanner.stop()
                    } else {
                        scanner.start(configuration: configStore.config, lastScores: session.lastCapturedScores) { result in
                            try session.record(result, in: context)
                        }
                    }
                }
                if !scanner.isMonitoring {
                    Text("Keep FlipTrack open while monitoring. Stop to edit scores.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.bar)
    }
}

#Preview {
    SessionView(session: Session.dummy(0, [[69068440, 12353550], [512353550, 1920]]))
        .environmentObject(ConfigStore())
}
