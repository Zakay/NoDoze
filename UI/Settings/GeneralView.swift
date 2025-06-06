import SwiftUI

struct GeneralView: View {
    @State private var startAtLogin = LoginItemManager.isEnabled
    @AppStorage("activateOnLaunch") private var activateOnLaunch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Toggle(isOn: $startAtLogin) {
                Text("Start at Login")
            }
            .onChange(of: startAtLogin) { _, newValue in
                LoginItemManager.toggle(as: newValue)
            }
            
            Toggle(isOn: $activateOnLaunch) {
                Text("Activate on Launch")
            }
            
            Spacer()
        }
        .padding(30)
        .frame(width: 400)
    }
}

struct GeneralView_Previews: PreviewProvider {
    static var previews: some View {
        GeneralView()
    }
} 