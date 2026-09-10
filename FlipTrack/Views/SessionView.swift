import SwiftUI
import SwiftData

struct SessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var configStore: ConfigStore
    @StateObject private var scanner = Scanner()
    @State private var showingPrefs = false
    @State private var showingManualEntry = false
    @State private var showingCamera = false
    let session: Session

    func formattedNumber(_ number: Int) -> String {
        number.formatted(.number.grouping(.automatic).locale(Locale(identifier: "de_DE")))
    }

    func color(for playerIndex: Int) -> Color { [Color.color1, Color.color2][playerIndex] }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                CurrentGameView(firstPlayer: session.firstPlayer,
                                secondPlayer: session.secondPlayer,
                                firstPlayerIndex: session.firstPlayerIndex,
                                colorFor: color(for:), gameNumber: session.upcomingGameNumber)
                TotalsView(playerTotals: session.playerTotals,
                           playerWins: session.playerWins,
                           highScores: session.highScores,
                           averageScores: session.averageScores,
                           colorFor: color(for:), formattedNumber: formattedNumber,
                           players: [session.player1, session.player2])
                if session.games?.isEmpty == false {
                    GamesPlayedView(games: session.games ?? [], formattedNumber: formattedNumber,
                                    colorFor: color(for:), allowsEditing: !scanner.isMonitoring)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "flag.checkered")
                            .font(.title2).foregroundStyle(.secondary)
                        Text("Your next game goes here").font(.subheadline.weight(.medium))
                        Text(scanner.isMonitoring ? "Confirmed scores will appear here." : "Scan the display, or add the scores yourself.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .safeAreaInset(edge: .bottom) { monitorControls }
        .preferredColorScheme(.dark)
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if scanner.isMonitoring {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(scanner.isPaused ? "Resume monitoring" : "Pause monitoring",
                           systemImage: scanner.isPaused ? "play.fill" : "pause.fill") {
                        if scanner.isPaused { startMonitoring() } else { scanner.pause() }
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("pauseMonitoring")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add scores", systemImage: "plus") { showingManualEntry = true }
                    .disabled(scanner.isMonitoring)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gear") {
                    scanner.stop()
                    showingPrefs = true
                }
            }
        }
        .onDisappear { if !showingCamera { scanner.stop() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { scanner.pause() }
        }
        .sheet(isPresented: $showingPrefs) { PreferencesView() }
        .sheet(isPresented: $showingManualEntry) { ManualGameView(session: session) }
        .fullScreenCover(isPresented: $showingCamera) {
            NavigationStack {
                VStack(spacing: 16) {
                    if scanner.isMonitoring && !scanner.isPaused {
                        CameraPreview(session: scanner.camera.session, showsScanArea: scanner.usesCenteredScanArea)
                    } else {
                        ContentUnavailableView("Camera paused", systemImage: "camera", description: Text(scanner.error ?? scanner.status))
                    }
                    Text(scanner.usesCenteredScanArea ? "Center the whole display inside the guide." : "Keep the whole display in view.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(scanner.error ?? scanner.status)
                        .font(.callout)
                }
                .padding()
                .background(.black)
                .navigationTitle("Camera view")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Scores", systemImage: "tablecells") { showingCamera = false } }
                }
            }
        }
    }

    private func startMonitoring() {
        scanner.start(configuration: configStore.config, lastScores: session.lastCapturedScores) { result in
            try session.record(result, in: context)
        }
    }

    private var monitorControls: some View {
        HStack(spacing: 12) {
            CameraButton(monitoring: scanner.isMonitoring, paused: scanner.isPaused) {
                if scanner.isMonitoring { scanner.stop() } else { startMonitoring() }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(scanner.isMonitoring ? (scanner.isPaused ? "Scan paused" : "Scanning") : "Scan off")
                    .font(.subheadline.weight(.semibold))
                Text(scanner.error ?? scanner.status)
                    .font(.caption)
                    .foregroundStyle(scanner.error == nil ? Color.secondary : .red)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Camera preview", systemImage: "camera") { showingCamera = true }
                .labelStyle(.iconOnly)
                .font(.title2)
                .frame(width: 44, height: 44)
                .disabled(!scanner.isMonitoring)
                .accessibilityIdentifier("showCameraPreview")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

}

#Preview {
    SessionView(session: Session.dummy(0, [[69068440, 12353550], [512353550, 1920]]))
        .environmentObject(ConfigStore())
}
