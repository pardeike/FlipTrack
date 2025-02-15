import SwiftUI
import _SwiftData_SwiftUI
import AVFoundation
import Foundation

struct Bar: View {
    let color1 = Color(hue: 0.54, saturation: 1, brightness: 1)
    let color2 = Color(hue: 0.07, saturation: 1, brightness: 1)
    func color(for playerIndex: Int) -> Color { [color1, color2][playerIndex] }
    let values: [Int]
    var f: CGFloat { CGFloat(values[0]) / CGFloat(values[0] + values[1]) }
    var body: some View {
        if values[0] + values[1] > 0 {
            GeometryReader { geo in
                Rectangle()
                    .fill(color(for: 1))
                    .frame(width: geo.size.width, height: 20)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(color(for: 0))
                            .frame(width: geo.size.width * f, height: 20)
                    }
                    .overlay(alignment: .leading) {
                        Text("\(values[0]) Andreas")
                            .padding(.leading, 6)
                            .foregroundStyle(.black).font(.caption)
                    }
                    .overlay(alignment: .trailing) {
                        Text("Fredrik \(values[1])")
                            .padding(.trailing, 6)
                            .foregroundStyle(.black).font(.caption)
                    }
            }
        }
    }
}

struct SessionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Session.date) private var sessions: [Session]
    @State var authorized = false
    
    func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    var reversedSessions: [Session] {
        sessions.sorted(using: SortDescriptor(\Session.date)).reversed()
    }
    
    func addSession() {
        let newSession = Session(date: Date())
        context.insert(newSession)
        try? context.save()
    }
    
    func deleteSession(at offsets: IndexSet) {
        offsets.forEach { index in
            let session = reversedSessions[index]
            context.delete(session)
        }
        try? context.save()
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(reversedSessions) { session in
                    NavigationLink {
                        SessionView(session: session)
                    } label: {
                        HStack(alignment: .center) {
                            Text(formattedDate(session.date)).font(.title2)
                            Spacer()
                            Bar(values: session.playerWins).padding()
                                .padding(.top, 6)
                        }
                    }
                }
                .onDelete(perform: deleteSession)
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: addSession) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .onAppear {
            if AVCaptureDevice.authorizationStatus(for: .video) != .authorized {
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    authorized = granted
                }
            } else {
                authorized = true
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    SessionsView()
}
