import SwiftUI

struct SectionHeader: View {
    var title: String
    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundColor(.gray)
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(Color(white: 0.1))
    }
}
