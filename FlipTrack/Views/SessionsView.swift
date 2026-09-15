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
                        Button("New session", systemImage: "plus", action: addSession)
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        Section("Session history") {
                        ForEach(sortedSessions) { session in
                            NavigationLink(value: session) {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(session.date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.headline)
                                        if session.id.uuidString == lastSessionID {
                                            Label("Continue", systemImage: "play.fill")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.tint)
                                        }
                                        Spacer()
                                        let count = session.games?.count ?? 0
                                        Text("\(session.date.formatted(date: .omitted, time: .shortened)) · \(count == 1 ? "1 game" : "\(count) games")")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    if session.games?.isEmpty == false {
                                        OverviewBalanceBar(values: session.playerWins, players: [session.player1, session.player2])
                                    } else {
                                        Text("\(session.firstPlayer) starts game \(session.upcomingGameNumber)")
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
            .safeAreaInset(edge: .bottom) {
                if !sortedSessions.isEmpty {
                    Button("New session", systemImage: "plus", action: addSession)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .buttonStyle(.borderedProminent)
                        .padding()
                        .background(.bar)
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
