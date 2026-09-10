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
        Group {
            if scanner.isMonitoring {
                AutomaticGameView(state: scanner.gameState, players: [session.player1, session.player2], gameNumber: session.upcomingGameNumber, isPaused: scanner.isPaused,
                                  playerWins: session.playerWins, lastScores: session.games?.max(by: { $0.nr < $1.nr })?.scores)
            } else {
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
                                   colorFor: color(for:), formattedNumber: formattedNumber, players: [session.player1, session.player2])
                        if session.games?.isEmpty == false {
                            GamesPlayedView(games: session.games ?? [], formattedNumber: formattedNumber,
                                            colorFor: color(for:))
                                .disabled(scanner.isMonitoring)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "flag.checkered")
                                    .font(.title2).foregroundStyle(.secondary)
                                Text("Your next game goes here").font(.subheadline.weight(.medium))
                                Text("Monitor the display, or add the scores yourself.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button("Add scores", systemImage: "plus") { showingManualEntry = true }
                                    .font(.subheadline)
                                    .disabled(scanner.isMonitoring)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
            }
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
        .onDisappear { scanner.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { scanner.pause() }
        }
        .sheet(isPresented: $showingPrefs) { PreferencesView() }
        .sheet(isPresented: $showingManualEntry) { ManualGameView(session: session) }
        .sheet(isPresented: $showingCamera) {
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
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { showingCamera = false } }
                }
            }
        }
    }

    private func startMonitoring() {
        scanner.start(configuration: configStore.config, lastScores: session.lastCapturedScores, firstPlayerIndex: session.firstPlayerIndex) { result in
            try session.record(result, in: context)
        }
    }

    private var monitorControls: some View {
        HStack(spacing: 12) {
            if scanner.isMonitoring {
                Button { showingCamera = true } label: {
                    ZStack(alignment: .bottomTrailing) {
                        if scanner.isPaused {
                            Color.black
                            Image(systemName: "pause.fill").foregroundStyle(.secondary)
                        } else if !showingCamera {
                            CameraPreview(session: scanner.camera.session, showsScanArea: scanner.usesCenteredScanArea)
                        }
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption).padding(6)
                            .background(.black.opacity(0.6), in: Circle())
                            .padding(6)
                    }
                    .frame(width: 88, height: 132)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Enlarge camera view")
            }
            VStack(spacing: 10) {
                Label(scanner.error ?? scanner.status,
                      systemImage: scanner.error != nil ? "exclamationmark.circle" : scanner.isMonitoring ? "viewfinder" : "camera")
                    .font(.callout)
                    .foregroundStyle(scanner.error == nil ? Color.secondary : .red)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.updatesFrequently)
                CameraButton(monitoring: scanner.isMonitoring) {
                    if scanner.isMonitoring {
                        scanner.stop()
                    } else {
                        startMonitoring()
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
