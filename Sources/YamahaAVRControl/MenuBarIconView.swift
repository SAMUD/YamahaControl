import SwiftUI

struct MenuBarIconView: View {
    @ObservedObject var controller: AVRController

    private var symbolName: String {
        if !controller.isReachable { return "speaker.slash.fill" }
        return controller.status?.power == "on" ? "hifispeaker.fill" : "hifispeaker"
    }

    private var iconColor: Color {
        guard controller.isReachable else { return .secondary }
        return controller.status?.power == "on" ? .green : .secondary
    }

    var body: some View {
        Image(systemName: symbolName)
            .foregroundStyle(iconColor)
    }
}
