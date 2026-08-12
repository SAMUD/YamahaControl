import SwiftUI

struct MenuBarIconView: View {
    @ObservedObject var controller: AVRController

    private var symbolName: String {
        if !controller.isReachable { return "hifispeaker.slash" }
        return controller.status?.power == "on" ? "hifispeaker.fill" : "hifispeaker"
    }

    var body: some View {
        Image(systemName: symbolName)
    }
}
