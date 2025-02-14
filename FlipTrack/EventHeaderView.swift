import SwiftUI

struct EventHeaderView: View {
    let formattedDate: String
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .foregroundColor(.white)
                    .padding()
            }
            Spacer()
            Text(formattedDate)
                .foregroundColor(.white)
                .font(.headline)
                .minimumScaleFactor(0.5)
            Spacer()
            Spacer().frame(width: 44)
        }
        .padding(.bottom, 10)
    }
}

#Preview {
    EventHeaderView(formattedDate: "2021-01-01") { }
        .preferredColorScheme(.dark)
}
