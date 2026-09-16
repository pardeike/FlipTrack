import SwiftUI
import SwiftData

struct SessionDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let session: Session
    @State private var player1 = ""
    @State private var player2 = ""
    @State private var date = Date()
    @State private var starter = 1
    @State private var gameNumber = ""
    @State private var saveError: String?

    private var valid: Bool {
        !player1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !player2.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (Int(gameNumber) ?? 0) > 0 &&
        session.games?.contains(where: { $0.nr == Int(gameNumber) }) != true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Players") {
                    TextField("First player", text: $player1)
                    TextField("Second player", text: $player2)
                }
                Section {
                    TextField("Game number", text: $gameNumber).keyboardType(.numberPad)
                    Picker("Left score / Player 1", selection: $starter) {
                        Text(player1).tag(0)
                        Text(player2).tag(1)
                    }
                    LabeledContent("Right score / Player 2", value: starter == 0 ? player2 : player1)
                } header: { Text("Game \(session.upcomingGameNumber) · machine order") }
                footer: {
                    Text("Set this before scanning, even if the game is already in progress. Existing score pairs stay assigned to their players.")
                }
                Section("Session") { DatePicker("Date", selection: $date) }
            }
            .navigationTitle("Players & game order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { Telemetry.shared.action("SessionDetailsView.cancel", session: session); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Telemetry.shared.action("session.saveEdits", session: session)
                        let before = SessionSnapshot(session)
                        session.player1 = player1.trimmingCharacters(in: .whitespacesAndNewlines)
                        session.player2 = player2.trimmingCharacters(in: .whitespacesAndNewlines)
                        session.date = date
                        session.startingPlayerOverride = starter
                        session.currentGameNumberOverride = Int(gameNumber)
                        do { try context.save(); Telemetry.shared.change("session.corrected", before: before, session: session); dismiss() }
                        catch { context.rollback(); Telemetry.shared.log("SessionDetailsView.error", ["message": error.localizedDescription]); saveError = error.localizedDescription }
                    }.disabled(!valid)
                }
            }
            .onDisappear { Telemetry.shared.action("SessionDetailsView.closed", session: session) }
            .onAppear {
                Telemetry.shared.action("SessionDetailsView.opened", session: session)
                player1 = session.player1
                player2 = session.player2
                date = session.date
                starter = session.firstPlayerIndex
                gameNumber = String(session.upcomingGameNumber)
            }
            .alert("Changes were not saved", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) { }
            } message: { Text(saveError ?? "") }
        }
    }
}
