import SwiftUI
import SwiftData

struct ManualGameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let session: Session
    @State private var firstScore = ""
    @State private var secondScore = ""
    @State private var saveError: String?
    @FocusState private var focusedPlayer: Int?

    private var scores: DisplayResult? {
        guard let left = Int(firstScore), let right = Int(secondScore),
              (0..<10_000_000_000).contains(left), (0..<10_000_000_000).contains(right) else { return nil }
        return DisplayResult(left: left, right: right)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    scoreField(session.firstPlayer, position: 0, text: $firstScore)
                    scoreField(session.secondPlayer, position: 1, text: $secondScore)
                } header: {
                    Text("Game \(session.upcomingGameNumber) · display order")
                } footer: {
                    Text("Enter the left score first, then the right. \(session.secondPlayer) will start the next game.")
                }
            }
            .navigationTitle("Add scores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(scores == nil)
                        .accessibilityIdentifier("saveGame")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(focusedPlayer == 0 ? "Next" : "Done") {
                        focusedPlayer = focusedPlayer == 0 ? 1 : nil
                    }
                }
            }
            .alert("Scores were not saved", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: { Text(saveError ?? "") }
            .onAppear { focusedPlayer = 0 }
        }
    }

    private func scoreField(_ name: String, position: Int, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(name, systemImage: "\(position + 1).square.fill")
                .foregroundStyle([Color.color1, Color.color2][position == 0 ? session.firstPlayerIndex : 1 - session.firstPlayerIndex])
                .font(.headline)
            TextField("Score", text: text)
                .keyboardType(.numberPad)
                .font(.title2.monospacedDigit())
                .focused($focusedPlayer, equals: position)
                .accessibilityLabel("\(name)'s score")
                .accessibilityIdentifier(position == 0 ? "leftScore" : "rightScore")
            if let number = Int(text.wrappedValue), number >= 0 {
                Text(number.formatted(.number.locale(Locale(identifier: "de_DE")))).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private func save() {
        guard let scores else { return }
        do {
            try session.record(scores, in: context)
            dismiss()
        } catch { saveError = error.localizedDescription }
    }
}
