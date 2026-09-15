import SwiftUI
import SwiftData

struct SessionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]
    @AppStorage("lastSessionID") private var lastSessionID = ""
    @State private var path: [Session] = []
    @State private var saveError: String?
    @State private var deletingSession: Session?
    var debugSessions: [Session]? = nil

    private var sortedSessions: [Session] {
        (debugSessions ?? sessions).sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                if sortedSessions.isEmpty {
                    ContentUnavailableView {
                        Label("Ready to play?", systemImage: "pin.circle")
                    } description: {
                        Text("Start a session to keep scores, track wins, and see who comes out ahead.")
                    } actions: {
                        Button("New Session", systemImage: "plus", action: addSession)
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section("Session history") {
                        ForEach(sortedSessions) { session in
                            NavigationLink(value: session) {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        if session.id.uuidString == lastSessionID {
                                            Image(systemName: "play.fill")
                                                .font(.caption)
                                                .foregroundStyle(.tint)
                                                .accessibilityLabel("Continue session")
                                        }
                                        Text(session.date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.headline)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                        Spacer(minLength: 8)
                                        if let topScorer = topScorer(in: session) {
                                            HStack(spacing: 3) {
                                                Image(systemName: "trophy.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.yellow)
                                                Text(topScorer)
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.primary)
                                            }
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                            .accessibilityElement(children: .ignore)
                                            .accessibilityLabel("\(topScorer) has the highest score")
                                        }
                                    }
                                    if session.games?.isEmpty == false {
                                        OverviewBalanceBar(values: session.playerWins, players: [session.player1, session.player2])
                                    } else {
                                        Text("\(session.firstPlayer) starts")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 6)
                            }
                            .listRowBackground(Color(white: 0.08))
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { deletingSession = session }
                            }
                        }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("FlipTrack")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Session.self) { SessionView(session: $0) }
            .safeAreaInset(edge: .bottom, spacing: 12) {
                if !sortedSessions.isEmpty {
                    Button("New Session", systemImage: "plus", action: addSession)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("Delete this session?", isPresented: Binding(get: { deletingSession != nil }, set: { if !$0 { deletingSession = nil } }), titleVisibility: .visible) {
            Button("Delete session", role: .destructive) {
                if let deletingSession {
                    context.delete(deletingSession)
                    _ = saveChanges()
                }
                deletingSession = nil
            }
        } message: { Text("All games and scores in this session will be removed.") }
        .alert("Changes were not saved", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    private func addSession() {
        let session = Session(date: .now)
        context.insert(session)
        if saveChanges() { path.append(session) }
    }

    private func topScorer(in session: Session) -> String? {
        let scores = session.highScores
        guard scores[0] != scores[1] else { return nil }
        return scores[0] > scores[1] ? session.player1 : session.player2
    }

    private func saveChanges() -> Bool {
        do { try context.save(); return true }
        catch {
            context.rollback()
            saveError = error.localizedDescription
            return false
        }
    }
}

#Preview {
    SessionsView(debugSessions: [Session.dummy(0, [[69068440, 12353550], [512353550, 1920]])])
}
