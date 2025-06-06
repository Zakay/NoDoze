import SwiftUI

struct SettingsView: View {
    @State private var selectedTab = "General"

    var body: some View {
        VStack {
            Picker("", selection: $selectedTab) {
                Text("General").tag("General")
                Text("About").tag("About")
            }
            .pickerStyle(.segmented)
            .padding()

            if selectedTab == "General" {
                GeneralView()
            } else {
                AboutView()
            }
            Spacer()
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
} 