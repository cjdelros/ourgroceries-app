import GroceriesCore
import SwiftUI

struct RootView: View {
    @State private var itemText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OurGroceries")
                .font(.headline)
            TextField("Add an item", text: $itemText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("itemTextField")
            Text("App shell ready")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 340)
    }
}

#Preview {
    RootView()
}
