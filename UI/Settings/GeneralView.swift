import SwiftUI

struct GeneralView: View {
    @State private var startAtLogin = LoginItemManager.isEnabled
    @AppStorage("activateOnLaunch") private var activateOnLaunch = false
    @AppStorage("defaultActivationDuration") private var defaultActivationDuration = DurationConfiguration.defaultOption.minutes

    var body: some View {
        Form {

            Picker("Default activation:", selection: $defaultActivationDuration) {
                ForEach(DurationConfiguration.allOptions, id: \.minutes) { option in
                    Text(option.name).tag(option.minutes)
                }
            }

            Spacer().frame(height: 20)

            Toggle("Start at Login", isOn: $startAtLogin)
                .onChange(of: startAtLogin) { _, newValue in
                    LoginItemManager.toggle(as: newValue)
                }
            
            Toggle("Activate on Launch", isOn: $activateOnLaunch)
        }
        .padding(20)
        .frame(width: 400)
    }
}

struct GeneralView_Previews: PreviewProvider {
    static var previews: some View {
        GeneralView()
    }
} 