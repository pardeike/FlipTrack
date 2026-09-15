import SwiftUI
import SwiftData

struct SessionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var configStore: ConfigStore
    @StateObject private var scanner = Scanner()
    @AppStorage("lastSessionID") private var lastSessionID = ""
    private enum Editor: String, Identifiable {
        case settings, scores, details
        var id: String { rawValue }
    }
    @State private var editor: Editor?
    @State private var editorAfterCamera: Editor?
    @State private var showingCamera = false
    @State private var recordingError: String?
    @State private var confirmingUndo = false
    @State private var confirmingRecapture = false
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
                    .contentShape(Rectangle())
                    .onTapGesture { openEditor(.details) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Edit player names and game order")
                HStack(spacing: 12) {
                    ForEach(0..<2) { index in
                        VStack(alignment: .leading, spacing: 6) {
                            Text([session.player1, session.player2][index])
                                .font(.headline)
                                .foregroundStyle(color(for: index))
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(session.playerWins[index])")
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                Text(session.playerWins[index] == 1 ? "win" : "wins")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(color(for: index).opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                if session.pendingCaptureScores.count == 2 {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Unsaved scores · Game \(session.upcomingGameNumber)", systemImage: "square.and.pencil")
                            .font(.headline)
                        Text("\(formattedNumber(session.pendingCaptureScores[0])) / \(formattedNumber(session.pendingCaptureScores[1]))")
                            .font(.title3.monospacedDigit())
                        Text("Left: \(session.firstPlayer) · Right: \(session.secondPlayer)")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Review & save") { openEditor(.scores) }
                                .buttonStyle(.borderedProminent)
                            Button("Discard", role: .destructive) {
                                scanner.pause(.editing)
                                do { try session.discardPendingCapture(in: context) }
                                catch { recordingError = error.localizedDescription }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                }
                if session.games?.isEmpty == false {
                    GamesPlayedView(games: session.games ?? [], formattedNumber: formattedNumber,
                                    colorFor: color(for:), onBeginEditing: { scanner.pause(.editing) })
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
                if session.games?.isEmpty == false {
                    TotalsView(playerTotals: session.playerTotals,
                               highScores: session.highScores,
                               averageScores: session.averageScores,
                               colorFor: color(for:), formattedNumber: formattedNumber,
                               players: [session.player1, session.player2])
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
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add scores", systemImage: "plus") { openEditor(.scores) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Players & game order", systemImage: "person.2") {
                        openEditor(.details)
                    }
                    Button("Undo last saved game", systemImage: "arrow.uturn.backward") {
                        scanner.pause(.editing)
                        confirmingUndo = true
                    }
                    .disabled(session.games?.isEmpty != false || !session.pendingCaptureScores.isEmpty)
                    Button("Capture same scores again", systemImage: "arrow.clockwise") {
                        scanner.pause(.editing)
                        confirmingRecapture = true
                    }
                    .disabled(!session.pendingCaptureScores.isEmpty)
                    Button("Scanner settings", systemImage: "viewfinder") {
                        openEditor(.settings)
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Session options")
            }

        }
        .confirmationDialog("Allow the previous score pair again?", isPresented: $confirmingRecapture, titleVisibility: .visible) {
            Button("Allow and start scanning") {
                session.allowRepeatedCapture = true
                session.rejectedCaptureSignatures = []
                do { try context.save(); startMonitoring() }
                catch { context.rollback(); recordingError = error.localizedDescription }
            }
        } message: {
            Text("Use this for another game with identical scores. The display can be saved again as a new game.")
        }
        .confirmationDialog("Reopen the last saved game?", isPresented: $confirmingUndo, titleVisibility: .visible) {
            Button("Undo save") {
                do { try session.undoLastGame(in: context) }
                catch { recordingError = error.localizedDescription }
            }
        } message: {
            Text("Its scores will become an editable draft. Its game number and player order will be restored.")
        }
        .alert("Changes could not be completed", isPresented: Binding(get: { recordingError != nil }, set: { if !$0 { recordingError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(recordingError ?? "") }
        .onAppear {
            lastSessionID = session.id.uuidString
            if session.scanningRequested { scanner.restorePausedSession() }
        }
        .onDisappear { if !showingCamera { scanner.stop() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                scanner.setPreview(false, configuration: configStore.config)
                scanner.pause(.background)
            } else if phase == .active, showingCamera {
                scanner.setPreview(true, configuration: configStore.config)
            }
        }
        .sheet(item: $editor) { item in
            switch item {
            case .settings: PreferencesView()
            case .scores: ManualGameView(session: session)
            case .details: SessionDetailsView(session: session)
            }
        }
        .onChange(of: showingCamera) { _, visible in
            scanner.setPreview(visible, configuration: configStore.config)
        }
        .fullScreenCover(isPresented: $showingCamera, onDismiss: {
            if let pending = editorAfterCamera {
                editorAfterCamera = nil
                editor = pending
            }
        }) {
            NavigationStack {
                VStack(spacing: 16) {
                    if scanner.testingPreview {
                        recognitionLog
                        Button("Camera preview", systemImage: "camera") {
                            scanner.setPreviewTest(false)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        if (scanner.isMonitoring && !scanner.isPaused) || scanner.previewRunning {
                            CameraPreview(session: scanner.camera.session, showsScanArea: scanner.usesCenteredScanArea)
                        } else {
                            ContentUnavailableView(scanner.previewError == nil ? "Starting camera…" : "Camera unavailable", systemImage: "camera", description: Text(scanner.previewError ?? "Preview only · Scores are not being recorded."))
                        }
                        Text(scanner.usesCenteredScanArea ? "Center the whole display inside the guide." : "Keep the whole display in view.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if !scanner.isMonitoring {
                            Button("Test live recognition", systemImage: "text.viewfinder") {
                                scanner.setPreviewTest(true)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    Text(scanner.isMonitoring && !scanner.isPaused ? scanner.error ?? scanner.status : "Preview only · Scores are not being recorded.")
                        .font(.callout)
                }
                .padding()
                .background(.black)
                .safeAreaInset(edge: .bottom) { monitorControls }
                .navigationTitle(scanner.testingPreview ? "Live recognition" : "Camera view")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var recognitionLog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if scanner.testReadings.isEmpty {
                        Text(scanner.previewError ?? "Waiting for recognized text…")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(scanner.testReadings) { reading in
                        Text(reading.text)
                            .font(.title2.monospaced())
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(reading.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: scanner.testReadings.last?.id) { _, id in
                if let id { proxy.scrollTo(id, anchor: .bottom) }
            }
            .overlay(alignment: .top) {
                if let error = scanner.previewError, !scanner.testReadings.isEmpty {
                    Text(error).font(.callout).padding().background(.regularMaterial)
                }
            }
        }
    }

    private func openEditor(_ destination: Editor) {
        scanner.pause(.editing)
        if showingCamera {
            editorAfterCamera = destination
            showingCamera = false
        } else {
            editor = destination
        }
    }

    private func startMonitoring() {
        guard session.pendingCaptureScores.isEmpty else {
            openEditor(.scores)
            return
        }
        do {
            try session.prepareCurrentGame(in: context)
            session.scanningRequested = true
            try context.save()
        } catch {
            recordingError = error.localizedDescription
            return
        }
        scanner.start(configuration: configStore.config, lastScores: session.lastCapturedScores, allowRepeatedScores: session.allowRepeatedCapture, rejectedSignatures: session.rejectedCaptureSignatures) { result in
            try session.stageCapture(result, in: context)
            try session.record(result, for: session.currentGameID, in: context)
        }
    }

    private func stopMonitoring() {
        scanner.stop()
        session.scanningRequested = false
        do { try context.save() }
        catch { context.rollback(); recordingError = error.localizedDescription }
    }

    private var monitorControls: some View {
        HStack(spacing: 12) {
            CameraButton(monitoring: scanner.isMonitoring, paused: scanner.isPaused) {
                if scanner.isMonitoring { stopMonitoring() } else { startMonitoring() }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(scanner.state.title)
                    .font(.subheadline.weight(.semibold))
                Text(scanner.error ?? scanner.status)
                    .font(.caption)
                    .foregroundStyle(scanner.error == nil ? Color.secondary : .red)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if scanner.isMonitoring {
                Button(scanner.isPaused ? "Resume scanning" : "Pause scanning",
                       systemImage: scanner.isPaused ? "play.fill" : "pause.fill") {
                    if scanner.isPaused { startMonitoring() } else { scanner.pause() }
                }
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .accessibilityIdentifier("pauseMonitoring")
            }
            Button(showingCamera ? "Score table" : "Camera preview", systemImage: showingCamera ? "tablecells" : "camera") { showingCamera.toggle() }
                .labelStyle(.iconOnly)
                .font(.title2)
                .frame(width: 44, height: 44)
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
