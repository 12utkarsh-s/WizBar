import SwiftUI

@main
struct WizBarApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(model)
        } label: {
            Image(systemName: model.anyOn ? "lightbulb.fill" : "lightbulb")
        }
        .menuBarExtraStyle(.window)
    }
}

struct PanelView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ForEach(model.bulbs) { bulb in
                BulbCard(bulb: bulb)
                Divider()
            }
            footer
        }
        .frame(width: 300)
        .task { await model.refreshAll() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await model.refreshAll() }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack {
                Toggle("Link both", isOn: $model.linked)
                Spacer()
                Button {
                    Task { await model.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh")
            }
            HStack {
                Toggle("Launch at login", isOn: $model.launchAtLogin)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
            }
        }
        .toggleStyle(.checkbox)
        .font(.callout)
        .padding(14)
    }
}

struct BulbCard: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var bulb: Bulb

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: bulb.isOn ? "lightbulb.fill" : "lightbulb")
                    .foregroundStyle(bulb.isOn && bulb.online ? bulb.displayColor : .secondary)
                Text(bulb.name).font(.headline)
                if !bulb.online {
                    Text("Offline").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Power", isOn: Binding(
                    get: { bulb.isOn },
                    set: { on in model.apply(from: bulb) { $0.setOn(on) } }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 12) {
                row("sun.max", "\(Int(bulb.brightness.rounded()))%") {
                    slider(\.brightness, Bulb.brightnessRange,
                           colors: [Color(white: 0.2), bulb.displayColor]) { $0.setBrightness($1) }
                }

                Picker("Mode", selection: Binding(
                    get: { bulb.mode },
                    set: { mode in model.apply(from: bulb) { $0.setMode(mode) } }
                )) {
                    ForEach(LightMode.allCases) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if bulb.mode == .white {
                    row("thermometer.medium", "\(Int(bulb.temp.rounded()))K") {
                        slider(\.temp, Bulb.tempRange,
                               colors: [Bulb.kelvinColor(2200), Bulb.kelvinColor(4350), Bulb.kelvinColor(6500)]) { $0.setTemp($1) }
                    }
                } else {
                    row("paintpalette", "") {
                        slider(\.hue, 0...1,
                               colors: stride(from: 0.0, through: 1.0, by: 1 / 6).map { Color(hue: $0, saturation: 1, brightness: 1) }) { $0.setHue($1) }
                    }
                    row("drop", "\(Int((bulb.saturation * 100).rounded()))%") {
                        slider(\.saturation, 0...1,
                               colors: [.white, Color(hue: bulb.hue, saturation: 1, brightness: 1)]) { $0.setSaturation($1) }
                    }
                }
            }
            .disabled(!bulb.online)
            .opacity(bulb.online ? 1 : 0.4)
        }
        .padding(14)
    }

    private func row(_ icon: String, _ value: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            content()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .trailing)
        }
    }

    private func slider(
        _ keyPath: KeyPath<Bulb, Double>,
        _ range: ClosedRange<Double>,
        colors: [Color],
        set: @escaping (Bulb, Double) -> Void
    ) -> some View {
        GradientSlider(
            value: Binding(
                get: { bulb[keyPath: keyPath] },
                set: { value in model.apply(from: bulb) { set($0, value) } }
            ),
            range: range,
            colors: colors,
            onEnded: { model.apply(from: bulb) { $0.commit() } }
        )
    }
}

/// A slider drawn over a gradient track, so the track previews the result.
struct GradientSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let colors: [Color]
    var onEnded: () -> Void = {}

    private let knob: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let travel = max(geo.size.width - knob, 1)
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .overlay(Capsule().strokeBorder(.primary.opacity(0.15)))
                    .frame(height: 8)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 0.5)
                    .frame(width: knob, height: knob)
                    .offset(x: travel * min(max(fraction, 0), 1))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let f = min(max((drag.location.x - knob / 2) / travel, 0), 1)
                        value = range.lowerBound + f * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in onEnded() }
            )
        }
        .frame(height: 18)
    }
}
