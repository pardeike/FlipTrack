import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State var image = UIImage()
    @State var scores = [0, 0]

    var body: some View {
        VStack {
            if apiKey.starts(with: "sk-") {
                Image(uiImage: image)
                    .resizable(resizingMode: .stretch)
                    .aspectRatio(contentMode: .fit)
                Button("Analyze") {
                    if let img = UIPasteboard.general.image {
                        image = img
                        Task {
                            scores = await Analyzer.extractScore(image)
                            if scores.count != 2 {
                                scores = [0, 0]
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                Spacer()
                HStack {
                    Spacer()
                    Text("\(scores[0])")
                    Spacer()
                    Text("\(scores[1])")
                    Spacer()
                }
            } else {
                Button("Paste API Key") { apiKey = UIPasteboard.general.string ?? "" }
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
