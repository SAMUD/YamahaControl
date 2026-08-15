import SwiftUI
import AppKit

/// Lautstärkeregler auf Basis von `NSSlider`, weil SwiftUIs `Slider` unter macOS keine
/// Mausrad-/Scroll-Ereignisse entgegennimmt. Zusätzlich wird zwischen "während des Ziehens"
/// (fortlaufend, angezeigt über `onChange`) und "Geste beendet" (Loslassen der Maustaste oder
/// ein Scrollrad-Tick, über `onCommit`) unterschieden, damit der Aufrufer bei Bedarf sofort
/// senden kann, statt auf eine Verzögerung zu warten.
struct VolumeSliderControl: NSViewRepresentable {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onChange: (Double) -> Void = { _ in }
    var onCommit: (Double) -> Void = { _ in }

    func makeNSView(context: Context) -> ScrollHandlingSlider {
        let slider = ScrollHandlingSlider()
        slider.sliderType = .linear
        slider.isContinuous = true
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.doubleValue = value
        slider.target = context.coordinator
        slider.action = #selector(Coordinator.sliderChanged(_:))
        slider.onScroll = { [weak coordinator = context.coordinator] delta in
            coordinator?.handleScroll(delta)
        }
        context.coordinator.slider = slider
        return slider
    }

    func updateNSView(_ nsView: ScrollHandlingSlider, context: Context) {
        context.coordinator.parent = self
        nsView.minValue = range.lowerBound
        nsView.maxValue = range.upperBound
        // Nicht während der Nutzer aktiv zieht oder scrollt überschreiben, sonst "rastet" der
        // Regler oder springt während der Geste hin und her.
        if !nsView.isBeingDragged, !nsView.isScrolling, abs(nsView.doubleValue - value) > 0.0005 {
            nsView.doubleValue = value
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject {
        var parent: VolumeSliderControl
        weak var slider: ScrollHandlingSlider?
        private var scrollSettleWorkItem: DispatchWorkItem?
        init(_ parent: VolumeSliderControl) { self.parent = parent }

        @objc func sliderChanged(_ sender: ScrollHandlingSlider) {
            let newValue = sender.doubleValue
            parent.value = newValue
            // NSSlider feuert bei jeder Mausbewegung dieselbe Action; über das aktuelle Event
            // lässt sich Beginn/Ende der Ziehgeste unterscheiden (gängiger, pragmatischer Trick,
            // da NSSlider selbst keine separaten Drag-Start/End-Callbacks anbietet).
            switch NSApp.currentEvent?.type {
            case .leftMouseDown:
                sender.isBeingDragged = true
                parent.onEditingChanged(true)
                parent.onChange(newValue)
            case .leftMouseUp:
                sender.isBeingDragged = false
                parent.onEditingChanged(false)
                parent.onCommit(newValue)
            default:
                parent.onChange(newValue)
            }
        }

        func handleScroll(_ delta: Double) {
            let clamped = min(max(parent.value + delta, parent.range.lowerBound), parent.range.upperBound)
            parent.value = clamped
            // Anders als bei der Maus-Ziehgeste aktualisiert AppKit die Anzeige des Reglers bei
            // scrollWheel-Ereignissen nicht selbst – ohne diese Zeile ändert sich zwar die
            // Lautstärke, der Regler bleibt aber optisch stehen.
            slider?.doubleValue = clamped

            // Solange noch Scroll-Ereignisse eintreffen, gilt die Geste als aktiv – verhindert,
            // dass ein zeitgleicher Hintergrund-Poll den Regler mitten in der Geste zurücksetzt.
            if slider?.isScrolling != true {
                slider?.isScrolling = true
                parent.onEditingChanged(true)
            }
            scrollSettleWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.slider?.isScrolling = false
                self?.parent.onEditingChanged(false)
            }
            scrollSettleWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)

            // Ein Scrollrad-/Trackpad-Gestus feuert viele Ereignisse pro Sekunde – wie beim Ziehen
            // muss das über `onChange` (debounced) laufen, sonst überflutet jeder einzelne Tick
            // das Netzwerk und der AVR antwortet verzögert/außer der Reihe (führt zu Springen und
            // kurzzeitig verschwindender Wiedergabeanzeige).
            parent.onChange(clamped)
        }
    }
}

final class ScrollHandlingSlider: NSSlider {
    var onScroll: ((Double) -> Void)?
    fileprivate var isBeingDragged = false
    fileprivate var isScrolling = false

    override func scrollWheel(with event: NSEvent) {
        let span = maxValue - minValue
        guard span > 0 else { return }
        let step: Double
        if event.hasPreciseScrollingDeltas {
            // Trackpad: feine, proportionale Schritte.
            step = Double(event.scrollingDeltaY) * 0.0015 * span
        } else {
            // Physisches Mausrad liefert meist nur ±1 pro Rastung – feste Schrittgröße je Tick.
            let direction: Double = event.scrollingDeltaY > 0 ? 1 : (event.scrollingDeltaY < 0 ? -1 : 0)
            step = direction * 0.03 * span
        }
        guard step != 0 else { return }
        onScroll?(step)
    }
}
