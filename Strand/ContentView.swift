import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "sun.and.horizon.fill")
                .imageScale(.large)
                .foregroundStyle(.orange)
            Text("Strand")
                .font(.largeTitle)
                .fontWeight(.bold)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
