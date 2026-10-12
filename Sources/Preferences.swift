import SwiftUI

struct PreferencesView: View {
    @ObservedObject private var model = AppModel.shared
    @State private var placeText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Where to look")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(sourceLine)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Button("Use Location Services") {
                    model.useDeviceLocation()
                }
                if model.showsLocationSettings {
                    Button("Location Settings…") {
                        model.openLocationSettings()
                    }
                }
                Text("Location Services is asked only if you choose it. Flightbar comes forward first, so macOS can show the prompt. It is used while the app is open.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("City, postal code, or latitude, longitude", text: $placeText)
                    .textFieldStyle(.roundedBorder)
                Button("Use this place") {
                    model.useTypedPlace(placeText)
                }
                Text("A city or postal code is sent to Apple’s geocoder to turn into coordinates. Latitude and longitude skip that. The position then stays on this Mac, except the public aircraft query, which includes those coordinates so the feed knows the area.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !model.placeNote.isEmpty {
                    Text(model.placeNote)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            Toggle("Fly across the menu bar", isOn: $model.fliesAcrossMenuBar)
            Text("Off unless you turn it on. The details card is the main view. Select an aircraft in the menu to open it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Show aircraft count on the icon", isOn: $model.showsPlaneCount)
            Text("Off unless you turn it on, so the icon stays the aircraft.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Toggle("Notify when an aircraft enters", isOn: $model.notificationsEnabled)
            TextField("Callsign, registration, or type", text: $model.notifyQuery)
                .textFieldStyle(.roundedBorder)
                .disabled(!model.notificationsEnabled)
            Text("Off until you turn it on. macOS asks for notification permission then. An alert fires when an aircraft enters the range. If you type something, it also has to match the callsign, registration, or type. The flag filter in the menu still applies. Alerts aimed at specific equipment and flight profiles are not in this version.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("The U filter is military (dbFlags & 1), the same aircraft tar1090 keeps when its U button is on. Interesting, PIA, and LADD are separate flags in the menu.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 460, alignment: .leading)
    }

    private var sourceLine: String {
        switch model.placeSource {
        case .device:
            return "Using Location Services."
        case .manual:
            return model.manualLabel.isEmpty ? "Using a place you entered." : "Using \(model.manualLabel)."
        case .unset:
            return "Choose Location Services, or enter a place. Flightbar works without Location Services."
        }
    }
}
