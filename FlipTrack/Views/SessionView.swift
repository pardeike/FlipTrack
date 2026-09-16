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
                                colorFor: color(for:), gameNumber: session.upcomingGameNumber,
                                currentPlayerIndex: session.currentPlayerIndex,
                                uncertain: session.progress.needsResync,
                                winner: session.sessionFinished ? session.raceWinnerIndex : nil,
                                ball: session.activeDisplay.turn?.ball)
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
                if session.activeDisplay.visible {
                    ActiveGameView(display: session.activeDisplay,
                                   tracking: scanner.isMonitoring && !scanner.isPaused && !scanner.isResyncing,
                                   formattedNumber: formattedNumber, colorFor: color(for:))
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
                                catch { Telemetry.shared.log("session.actionError", ["message": error.localizedDescription]); recordingError = error.localizedDescription }
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
        .disabled(scanner.isResyncing)
        .overlay { recoveryOverlay }
        .safeAreaInset(edge: .bottom) { monitorControls }
        .navigationBarBackButtonHidden(scanner.isResyncing)
        .preferredColorScheme(.dark)
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add scores", systemImage: "plus") { openEditor(.scores) }.disabled(scanner.isResyncing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Players & game order", systemImage: "person.2") {
                        openEditor(.details)
                    }
                    Button("Undo last saved game", systemImage: "arrow.uturn.backward") {
                        scanner.pause(.editing)
                        Telemetry.shared.action("game.requestUndo", session: session)
                        confirmingUndo = true
                    }
                    .disabled(session.games?.isEmpty != false || !session.pendingCaptureScores.isEmpty)
                    Button("Capture same scores again", systemImage: "arrow.clockwise") {
                        scanner.pause(.editing)
                        Telemetry.shared.action("scanner.requestRepeated", session: session)
                        confirmingRecapture = true
                    }
                    .disabled(session.sessionFinished || !session.pendingCaptureScores.isEmpty)
                    Button("Scanner settings", systemImage: "viewfinder") {
                        openEditor(.settings)
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Session options")
                .disabled(scanner.isResyncing)
            }

        }
        .confirmationDialog("Allow the previous score pair again?", isPresented: $confirmingRecapture, titleVisibility: .visible) {
            Button("Allow and start scanning") {
                Telemetry.shared.action("scanner.allowRepeated", session: session)
                session.allowRepeatedCapture = true
                session.rejectedCaptureSignatures = []
                do { try context.save(); startMonitoring() }
                catch { context.rollback(); Telemetry.shared.log("session.actionError", ["message": error.localizedDescription]); recordingError = error.localizedDescription }
            }
        } message: {
            Text("Use this for another game with identical scores. The display can be saved again as a new game.")
        }
        .confirmationDialog("Reopen the last saved game?", isPresented: $confirmingUndo, titleVisibility: .visible) {
            Button("Undo save") {
                Telemetry.shared.action("game.confirmUndo", session: session)
                do { try session.undoLastGame(in: context) }
                catch { Telemetry.shared.log("session.actionError", ["message": error.localizedDescription]); recordingError = error.localizedDescription }
            }
        } message: {
            Text("Its scores will become an editable draft. Its game number and player order will be restored.")
        }
        .alert("Changes could not be completed", isPresented: Binding(get: { recordingError != nil }, set: { if !$0 { recordingError = nil } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(recordingError ?? "") }
        #if FLIPTRACK_DEVICE_TESTING
        .task { await DeviceCheck.run(scanner:scanner,session:session,context:context,start:startMonitoring) }
        #endif
        .onAppear {
            Telemetry.shared.action("session.open", session: session)
            lastSessionID = session.id.uuidString
            if session.scanningRequested { scanner.restorePausedSession() }
        }
        .onDisappear {
            Telemetry.shared.action("session.disappear", session: session)
            if !showingCamera { scanner.stop() }
        }
        .onChange(of: SessionSnapshot(session)) { before, _ in
            Telemetry.shared.change("session.observedChange", before: before, session: session)
            scanner.refreshContext()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                scanner.setPreview(false, configuration: configStore.config)
                scanner.pause(.background)
            } else if phase == .active, showingCamera {
                scanner.setPreview(true, configuration: configStore.config)
            }
        }
        .onChange(of: confirmingUndo) { _, open in Telemetry.shared.log("dialog.undo", ["open": open]) }
        .onChange(of: confirmingRecapture) { _, open in Telemetry.shared.log("dialog.recapture", ["open": open]) }
        .sheet(item: $editor, onDismiss: {
            Telemetry.shared.action("editor.dismiss", session: session)
            scanner.refreshContext()
        }) { item in
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
                Group {
                    if scanner.testingPreview {
                        recognitionLog
                            .padding(.horizontal)
                    } else if (scanner.isMonitoring && !scanner.isPaused) || scanner.previewRunning {
                        CameraPreview(session: scanner.camera.session, showsScanArea: scanner.usesCenteredScanArea)
                    } else if let error = scanner.previewError {
                        ContentUnavailableView("Camera unavailable", systemImage: "camera", description: Text(error))
                    } else {
                        ProgressView("Starting camera…")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .overlay { recoveryOverlay }
                .safeAreaInset(edge: .bottom) { monitorControls }
                .navigationTitle(scanner.testingPreview ? "Recognition test" : "Camera")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if !scanner.isMonitoring {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(scanner.testingPreview ? "Camera preview" : "Test recognition",
                                   systemImage: scanner.testingPreview ? "camera" : "text.viewfinder") {
                                scanner.setPreviewTest(!scanner.testingPreview)
                            }
                            .labelStyle(.iconOnly)
                            .accessibilityIdentifier("toggleRecognitionTest")
                        }
                    }
                }
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
        Telemetry.shared.action("editor.open.\(destination.rawValue)", session: session)
        scanner.pause(.editing)
        if showingCamera {
            editorAfterCamera = destination
            showingCamera = false
        } else {
            editor = destination
        }
    }

    private func startMonitoring() {
        Telemetry.shared.action("scanner.startOrResume", session: session)
        guard !session.sessionFinished else { return }
        guard session.pendingCaptureScores.isEmpty else {
            openEditor(.scores)
            return
        }
        do {
            try session.prepareCurrentGame(in: context)
            session.scanningRequested = true
            try context.save()
        } catch {
            Telemetry.shared.log("session.actionError", ["message": error.localizedDescription]); recordingError = error.localizedDescription
            return
        }
        let session = session
        let context = context
        scanner.start(configuration: configStore.config, current: { SessionSnapshot(session) }, update: { progress, id in
            try session.updateProgress(progress, for: id, in: context)
        }, save: { result, id in
            guard id == session.currentGameID else { throw Session.RecordingError.staleGame }
            try session.stageCapture(result, in: context)
            try session.record(result, for: id, in: context)
        })
    }

    @ViewBuilder private var recoveryOverlay: some View {
        if scanner.isResyncing {
            ZStack {
                Color.black.opacity(0.5).ignoresSafeArea()
                VStack(spacing: 20) {
                    ProgressView("Scanning…")
                    Button("Cancel") { scanner.cancelResync() }
                        .accessibilityIdentifier("cancelResync")
                }
                .padding(28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func stopMonitoring() {
        Telemetry.shared.action("scanner.stopButton", session: session)
        scanner.stop()
        session.scanningRequested = false
        do { try context.save() }
        catch { context.rollback(); Telemetry.shared.log("session.actionError", ["message": error.localizedDescription]); recordingError = error.localizedDescription }
    }

    private var monitorControls: some View {
        HStack(spacing: 12) {
            CameraButton(monitoring: scanner.isMonitoring, paused: scanner.isPaused) {
                if scanner.isMonitoring { stopMonitoring() } else { startMonitoring() }
            }
            .disabled(scanner.isResyncing || session.sessionFinished)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.sessionFinished ? "Session complete" : scanner.testingPreview ? "Testing recognition" : showingCamera && !scanner.isMonitoring && scanner.error == nil ? "Preview only" : scanner.state.title)
                    .font(.subheadline.weight(.semibold))
                Text(Telemetry.shared.failure ?? (scanner.testingPreview ? "Scores are not saved." : scanner.error ?? scanner.status))
                    .font(.caption)
                    .foregroundStyle(scanner.error == nil && Telemetry.shared.failure == nil ? Color.secondary : .red)
                    .lineLimit(scanner.error == nil && Telemetry.shared.failure == nil ? 1 : 2)
                    .minimumScaleFactor(0.7)
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
                .disabled(scanner.isResyncing)
                Button("Resync", systemImage: "arrow.right.to.line") { scanner.resync() }
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
                    .disabled(scanner.isPaused || scanner.isResyncing)
                    .accessibilityIdentifier("resyncTracking")
                    .accessibilityHint("Read the display again to recover a missed turn or final score")
            }
            Button(showingCamera ? "Close" : "Camera preview", systemImage: showingCamera ? "xmark" : "camera") { showingCamera.toggle() }
                .labelStyle(.iconOnly)
                .font(.title2)
                .frame(width: 44, height: 44)
                .accessibilityIdentifier("showCameraPreview")
                .disabled(scanner.isResyncing)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background {
            if showingCamera {
                Color.black
            } else {
                Rectangle().fill(.bar)
            }
        }
    }

}

#Preview {
    SessionView(session: Session.dummy(0, [[69068440, 12353550], [512353550, 1920]]))
        .environmentObject(ConfigStore())
}
