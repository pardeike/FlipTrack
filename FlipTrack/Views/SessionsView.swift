import SwiftUI
import _SwiftData_SwiftUI
import AVFoundation
import Foundation

struct SessionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Session.date) private var sessions: [Session]
    var debugSessions: [Session]? = nil
    
    func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    var sortedSessions: [Session] {
        (debugSessions ?? sessions).sorted(using: SortDescriptor(\Session.date)).reversed()
    }
    
    func addSession() {
        let newSession = Session(date: Date())
        context.insert(newSession)
        try? context.save()
    }
    
    func deleteSession(at offsets: IndexSet) {
        offsets.forEach { index in
            let session = sortedSessions[index]
            context.delete(session)
        }
        try? context.save()
    }

    var body: some View {
        NavigationStack {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .padding(.horizontal)
                .overlay {
                    LinearGradient(gradient: Gradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .clear, location: 0.25),
                        .init(color: .clear, location: 0.75),
                        .init(color: .black, location: 1),
                    ]), startPoint: .leading, endPoint: .trailing)
                }
                .overlay {
                    LinearGradient(gradient: Gradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .clear, location: 0.2),
                        .init(color: .clear, location: 0.8),
                        .init(color: .black, location: 1),
                    ]), startPoint: .top, endPoint: .bottom)
                }
                .padding(.bottom, -20)
            List {
                ForEach(sortedSessions) { session in
                    NavigationLink {
                        SessionView(session: session)
                    } label: {
                        HStack(alignment: .center) {
                            Text(formattedDate(session.date)).font(.title2)
                            Spacer()
                            OverviewBalanceBar(values: session.playerWins).padding()
                                .padding(.top, 6)
                        }
                    }
                }
                .onDelete(perform: deleteSession)
            }
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: addSession) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    SessionsView(debugSessions: [
        Session.dummy(-1, [[69068440, 12353550], [512353550, 1920]]),
        Session.dummy(0, [[10000, 10000]])
    ])
}
