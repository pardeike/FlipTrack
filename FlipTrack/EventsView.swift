import SwiftUI
import Foundation

struct EventsView: View {
    @State private var events: [Event] = [
        Event(date: Date()),
        Event(date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!),
        Event(date: Calendar.current.date(byAdding: .day, value: -2, to: Date())!)
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(events) { event in
                    NavigationLink {
                        EventView(event: event)
                    } label: {
                        Text(formattedDate(event.date))
                    }
                }
            }
            .navigationTitle("Events")
        }
        .preferredColorScheme(.dark)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

#Preview {
    EventsView()
}
