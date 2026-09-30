import AppKit
import Combine
import ServiceManagement
import SwiftUI

enum LightMode: String, CaseIterable, Identifiable {
    case white = "White"
    case color = "Color"
    var id: Self { self }
}

@MainActor
final class Bulb: ObservableObject, Identifiable {
    static let brightnessRange: ClosedRange<Double> = 10...100
    static let tempRange: ClosedRange<Double> = 2200...6500

    let name: String
    let host: String
    nonisolated var id: String { host }

    @Published var online = true
    @Published var isOn = false
    @Published var brightness: Double = 100
    @Published var mode: LightMode = .white
    @Published var temp: Double = 3000
    @Published var hue: Double = 0.08
    @Published var saturation: Double = 1

    /// Params not yet sent; merged so only the latest value of each goes out.
    private var pending: [String: Any] = [:]
    /// True during the cooldown after a send (limits updates to ~10/sec while dragging).
    private var throttling = false

    init(name: String, host: String) {
        self.name = name
        self.host = host
    }

    var displayColor: Color {
        switch mode {
        case .white: Self.kelvinColor(temp)
        case .color: Color(hue: hue, saturation: saturation, brightness: 1)
        }
    }

    func refresh() async {
        let pilot = await WizClient.getPilot(host)
        // Don't clobber a value the user is dragging right now.
        guard !throttling else { return }
        guard let pilot else {
            online = false
            return
        }
        online = true
        isOn = pilot.state
        if let dimming = pilot.dimming { brightness = Double(dimming) }
        if let r = pilot.r, let g = pilot.g, let b = pilot.b {
            mode = .color
            let color = NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
            hue = color.hueComponent
            saturation = color.saturationComponent
        } else {
            mode = .white
            if let temp = pilot.temp { self.temp = Double(temp) }
        }
    }

    // MARK: Controls (adjusting anything but power also turns the bulb on)

    func setOn(_ on: Bool) {
        isOn = on
        send(["state": on])
    }

    func setBrightness(_ value: Double) {
        brightness = value
        isOn = true
        send(["state": true, "dimming": Int(value.rounded())])
    }

    func setTemp(_ value: Double) {
        temp = value
        mode = .white
        isOn = true
        send(whiteParams)
    }

    func setHue(_ value: Double) {
        hue = value
        mode = .color
        isOn = true
        send(colorParams)
    }

    func setSaturation(_ value: Double) {
        saturation = value
        mode = .color
        isOn = true
        send(colorParams)
    }

    func setMode(_ newMode: LightMode) {
        mode = newMode
        isOn = true
        send(newMode == .white ? whiteParams : colorParams)
    }

    /// Resends the full current state; called when a drag ends in case a UDP packet was dropped.
    func commit() {
        guard isOn else { return send(["state": false]) }
        send(mode == .white ? whiteParams : colorParams)
    }

    // MARK: Sending

    private var whiteParams: [String: Any] {
        ["state": true, "dimming": Int(brightness.rounded()), "temp": Int(temp.rounded())]
    }

    private var colorParams: [String: Any] {
        let color = NSColor(hue: hue, saturation: saturation, brightness: 1, alpha: 1)
            .usingColorSpace(.sRGB) ?? .white
        return [
            "state": true,
            "dimming": Int(brightness.rounded()),
            "r": Int((color.redComponent * 255).rounded()),
            "g": Int((color.greenComponent * 255).rounded()),
            "b": Int((color.blueComponent * 255).rounded()),
        ]
    }

    private func send(_ params: [String: Any]) {
        // White and color modes are mutually exclusive on the bulb.
        if params["temp"] != nil { ["r", "g", "b"].forEach { pending.removeValue(forKey: $0) } }
        if params["r"] != nil { pending.removeValue(forKey: "temp") }
        pending.merge(params) { $1 }
        if !throttling { flush() }
    }

    private func flush() {
        guard !pending.isEmpty else {
            throttling = false
            return
        }
        let message = WizClient.setPilotMessage(pending)
        pending = [:]
        throttling = true

        let host = host
        Task {
            if !(await WizClient.setPilot(host, message: message)) { online = false }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            flush()
        }
    }

    static func kelvinColor(_ kelvin: Double) -> Color {
        let f = (kelvin - tempRange.lowerBound) / (tempRange.upperBound - tempRange.lowerBound)
        let warm = (r: 1.0, g: 0.62, b: 0.28)
        let cool = (r: 0.80, g: 0.88, b: 1.0)
        return Color(
            red: warm.r + (cool.r - warm.r) * f,
            green: warm.g + (cool.g - warm.g) * f,
            blue: warm.b + (cool.b - warm.b) * f
        )
    }
}

@MainActor
final class AppModel: ObservableObject {
    let bulbs = [
        Bulb(name: "Bedroom Lamp", host: "192.168.1.XX"), // Add your devices here
        
    ]

    @Published var linked = UserDefaults.standard.bool(forKey: "linked") {
        didSet { UserDefaults.standard.set(linked, forKey: "linked") }
    }

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Re-publish bulb changes so the menu bar icon tracks on/off state.
        for bulb in bulbs {
            bulb.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
        // Background poll keeps the icon accurate if lights change elsewhere.
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in Task { await self?.refreshAll() } }
            .store(in: &cancellables)
        Task { await refreshAll() }
    }

    var anyOn: Bool { bulbs.contains { $0.online && $0.isOn } }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for bulb in bulbs {
                group.addTask { await bulb.refresh() }
            }
        }
    }

    /// Applies a change to one bulb, or to every reachable bulb when linked.
    func apply(from bulb: Bulb, _ change: (Bulb) -> Void) {
        if linked {
            bulbs.filter { $0 === bulb || $0.online }.forEach(change)
        } else {
            change(bulb)
        }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("WizBar: launch at login change failed: \(error)")
            }
            objectWillChange.send()
        }
    }
}
