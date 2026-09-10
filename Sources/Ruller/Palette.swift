import SwiftUI
import RullerCore

private let accent = Color(red: 0.90, green: 0.28, blue: 0.30)

struct PaletteView: View {
    @ObservedObject var model: RullerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Image(systemName: "ruler").font(.system(size: 24, weight: .medium)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ruller").font(.system(size: 21, weight: .semibold, design: .rounded))
                    Text("A little clarity, on any screen.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.showSettings?() } label: { Image(systemName: "gearshape").frame(width: 22, height: 24) }
                    .buttonStyle(.borderless).help("Customize keyboard shortcuts").accessibilityLabel("Keyboard shortcuts")
                Button { model.toggleVisibility() } label: {
                    Image(systemName: model.isVisible ? "eye" : "eye.slash").frame(width: 24, height: 24)
                }.buttonStyle(.borderless).help("Show or hide all lines · \(model.shortcutLabel(.visibility))")
                .accessibilityLabel(model.isVisible ? "Hide lines" : "Show lines")
            }

            HStack(spacing: 4) {
                modeButton("Click through", symbol: "cursorarrow", editing: false)
                modeButton("Edit lines", symbol: "pencil.tip", editing: true)
            }.padding(4).background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Button { model.toggleLoupe?() } label: {
                    Label(model.loupeEnabled ? "Hide loupe" : "Loupe", systemImage: "plus.magnifyingglass")
                }.controlSize(.small).help("Magnify the pixels under your cursor · \(model.shortcutLabel(.loupe))")
                Spacer()
                Picker("Loupe zoom", selection: $model.loupeZoom) {
                    ForEach([4, 8, 16], id: \.self) { Text("\($0)×").tag($0) }
                }.labelsHidden().frame(width: 62).controlSize(.small)
            }
            if let error = model.loupeError {
                VStack(alignment: .leading, spacing: 5) {
                    Text(error).font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("Open Screen Recording settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                    }.buttonStyle(.borderless).font(.system(size: 11))
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                sectionTitle("ADD A GUIDE")
                HStack(spacing: 8) {
                    ForEach(GuideKind.allCases, id: \.self) { kind in
                        Button { model.arm(kind) } label: {
                            VStack(spacing: 7) {
                                Image(systemName: kind.symbol).font(.system(size: 17, weight: .medium))
                                Text(kind.title).font(.system(size: 11, weight: .medium))
                            }.frame(maxWidth: .infinity).frame(height: 54)
                            .background(model.tool == kind ? accent.opacity(0.13) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(model.tool == kind ? accent : Color.primary.opacity(0.09), lineWidth: 1))
                        }.buttonStyle(.plain).help("\(kind == .segment ? "Drag" : "Click") anywhere on a screen to place a \(kind.title.lowercased()) guide")
                    }
                }
                Text(instruction).font(.system(size: 11)).foregroundStyle(.secondary).frame(height: 28, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    sectionTitle("GUIDES")
                    Text("\(model.visibleGuides.count)").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    if model.displays.count > 1 {
                        Picker("Display", selection: Binding(get: { model.activeDisplayID }, set: {
                            model.activeDisplayID = $0; model.select(model.visibleGuides.first?.id)
                        })) {
                            ForEach(model.displays) { Text($0.name).tag($0.id) }
                        }.labelsHidden().frame(maxWidth: 155).controlSize(.small)
                    }
                    Button("Clear all") { model.clear() }.buttonStyle(.borderless).font(.system(size: 11))
                        .disabled(model.guides.isEmpty).help("Remove all guides. Undo with ⌘Z.")
                }
                ScrollView {
                    VStack(spacing: 3) {
                        if model.visibleGuides.isEmpty {
                            VStack(spacing: 6) {
                                Text("Your screen, with a reference line.").font(.system(size: 12, weight: .medium))
                                Text("Choose a guide above to get started.").font(.system(size: 11)).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).frame(height: 89)
                        } else {
                            ForEach(model.visibleGuides) { guide in
                                Button { model.select(guide.id, extending: !NSEvent.modifierFlags.intersection([.shift, .command]).isEmpty) } label: {
                                    HStack(spacing: 9) {
                                        RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: guide.color.nsColor)).frame(width: 3, height: 19)
                                        Image(systemName: guide.kind.symbol).frame(width: 15)
                                        Text(guide.kind.title).font(.system(size: 12))
                                        if model.attachments[guide.id] != nil { Image(systemName: "link").font(.system(size: 10)).foregroundStyle(.secondary) }
                                        Spacer()
                                        Text(model.valueLabel(for: guide)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                                    }.padding(.horizontal, 9).padding(.vertical, 7)
                                    .background(model.selectedIDs.contains(guide.id) ? Color.primary.opacity(0.075) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel("\(guide.kind.title) guide, \(model.valueLabel(for: guide))")
                            }
                        }
                    }.padding(4)
                }.frame(height: 120).background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.08)))
                HStack(spacing: 10) {
                    Button("Select all") { model.selectAll() }.disabled(model.visibleGuides.isEmpty)
                    Spacer()
                    Text("\(model.selectedIDs.count) selected").foregroundStyle(.secondary)
                    Button("Attach…") { model.armWindowPicker() }
                        .disabled(model.selectedIDs.isEmpty).help("Attach selected guides: click the window to follow").accessibilityLabel("Attach selection to a window")
                    Button("Detach") { model.detachSelection() }
                        .disabled(!model.selectedIDs.contains(where: { model.attachments[$0] != nil }))
                        .help("Detach selected guides from their window").accessibilityLabel("Detach selection from window")
                }.buttonStyle(.borderless).font(.system(size: 11))
                if !model.isPickingWindow, let link = model.selectedID.flatMap({ model.attachments[$0] }) {
                    Text("Following \(link.window.title)").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                } else if let message = model.attachmentMessage {
                    Text(message).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                }
            }

            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    sectionTitle(model.selected == nil ? "NEW GUIDE STYLE" : model.selectedIDs.count > 1 ? "SELECTED GUIDES" : "SELECTED GUIDE")
                    Spacer()
                    Button { model.duplicate() } label: { Image(systemName: "plus.square.on.square") }
                        .buttonStyle(.borderless).disabled(model.selected == nil).help("Duplicate selected guide · ⌘D").accessibilityLabel("Duplicate selected guide")
                    Button { model.deleteSelected() } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).disabled(model.selected == nil).help("Delete selected guide").accessibilityLabel("Delete selected guide")
                }
                HStack(spacing: 9) {
                    ForEach(GuideColor.allCases, id: \.self) { color in
                        Button { model.setColor(color) } label: {
                            Circle().fill(Color(nsColor: color.nsColor)).frame(width: 19, height: 19)
                                .overlay(Circle().stroke(Color.primary.opacity(0.18), lineWidth: 0.5))
                                .padding(3).overlay(Circle().stroke(model.color == color ? Color.primary.opacity(0.7) : .clear, lineWidth: 1.5))
                        }.buttonStyle(.plain).accessibilityLabel("\(color.rawValue.capitalized) line color")
                    }
                    Spacer(minLength: 0)
                    Picker("Width", selection: Binding(get: { model.width }, set: { model.setWidth($0) })) {
                        ForEach([1, 2, 3, 4, 6, 8], id: \.self) { Text("\($0) px").tag($0) }
                    }.labelsHidden().frame(width: 67).controlSize(.small).help("Line thickness in display backing pixels")
                }
                HStack(spacing: 10) {
                    Text("Opacity").font(.system(size: 12)).frame(width: 48, alignment: .leading)
                    Slider(value: Binding(get: { model.opacity }, set: { model.setOpacity($0) }), in: 0.05...1) { editing in
                        if editing { model.beginTransaction() } else { model.commitTransaction() }
                    }.accessibilityLabel("Line opacity")
                    Text("\(Int((model.opacity * 100).rounded()))%").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
                }
                Toggle("High contrast", isOn: $model.highContrast).toggleStyle(.checkbox).font(.system(size: 11))
                    .help("A black-and-white outline keeps guides visible on light and dark backgrounds. Measurements use the original line coordinates.")
                if let selected = model.selected, model.selectedIDs.count == 1 {
                    HStack(spacing: 8) {
                        if selected.kind != .horizontal {
                            CoordinateInput(title: "X", value: selected.start.x * model.factor, suffix: model.unit.suffix) { model.setCoordinate($0, axis: "x") }
                        }
                        if selected.kind != .vertical {
                            CoordinateInput(title: "Y", value: selected.start.y * model.factor, suffix: model.unit.suffix) { model.setCoordinate($0, axis: "y") }
                        }
                    }.id(selected.id)
                    if selected.kind == .segment {
                        HStack(spacing: 8) {
                            CoordinateInput(title: "X₂", value: selected.end.x * model.factor, suffix: model.unit.suffix) { model.setCoordinate($0, axis: "x2") }
                            CoordinateInput(title: "Y₂", value: selected.end.y * model.factor, suffix: model.unit.suffix) { model.setCoordinate($0, axis: "y2") }
                        }.id("end-\(selected.id)")
                    }
                }
            }

            Divider()
            HStack {
                Toggle("Labels", isOn: $model.showLabels).toggleStyle(.checkbox).font(.system(size: 12))
                Toggle("Distances", isOn: $model.showDistances).toggleStyle(.checkbox).font(.system(size: 12))
                    .help("Show gaps between neighboring horizontal or vertical guides. Drag a distance label in Edit mode to reposition the measurements.")
                Spacer()
                Picker("Coordinates", selection: $model.unit) {
                    Text("Screen pt").tag(MeasurementUnit.points)
                    Text("Device px").tag(MeasurementUnit.pixels)
                }.labelsHidden().frame(width: 105).controlSize(.small)
            }
            if model.showDistances && model.visibleGaps.isEmpty {
                Text("Add two horizontal or vertical guides to measure a gap.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text("\(model.shortcutLabel(.edit))  Edit / click through"); Spacer(); Text("Esc  Finish") }
                Text("Shift-click or drag empty space to select several lines")
                Text("Arrows: 1 \(model.unit.suffix) · Shift: 10 · Option: 1 device px")
                Text("\(format(model.selectedDisplay?.geometry.scale ?? 1))× display · 1 pt = \(format(model.selectedDisplay?.geometry.scale ?? 1)) device px")
                    .help("Screen points roughly match CSS pixels at 100% browser zoom. Browser zoom and display scaling affect the relationship. Device pixels are macOS backing pixels.")
            }.font(.system(size: 10)).foregroundStyle(.secondary)
            if let error = model.persistenceError ?? model.shortcutWarning {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange)
            }
        }
        .padding(20).frame(width: 350).background(.regularMaterial)
        .tint(accent)
    }

    private var instruction: String {
        if model.isPickingWindow { return "Click the window your selected lines should follow. Esc cancels." }
        if let tool = model.tool { return tool == .segment ? "Drag to draw. Hold Shift for a straight angle." : "Click anywhere to place it. Drag to adjust." }
        if !model.isVisible { return "Lines are hidden. Use the eye button to show them." }
        return model.isEditing ? "Drag guides or distance labels. Press Esc when ready." : "Windows underneath work normally. Lines stay put."
    }

    private func sectionTitle(_ value: String) -> some View {
        Text(value).font(.system(size: 10, weight: .semibold)).tracking(1.0).foregroundStyle(.secondary)
    }

    private func modeButton(_ title: String, symbol: String, editing: Bool) -> some View {
        Button { model.setEditing(editing) } label: {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .foregroundStyle(model.isEditing == editing ? Color.primary : Color.secondary)
                .background(model.isEditing == editing ? Color(nsColor: .controlBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
    }
}

private struct CoordinateInput: View {
    let title: String
    let value: Double
    let suffix: String
    let commit: (Double) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            TextField(title, text: $text).textFieldStyle(.plain).multilineTextAlignment(.trailing)
                .focused($focused).onSubmit { save(); focused = false }
                .accessibilityLabel("\(title) coordinate in \(suffix)")
            Text(suffix).foregroundStyle(.tertiary)
        }.font(.system(size: 12, design: .monospaced)).padding(8)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            .onAppear { text = format(value) }
            .onChange(of: value) { v in if !focused { text = format(v) } }
            .onChange(of: suffix) { _ in focused = false; text = format(value) }
            .onChange(of: focused) { f in if !f { save() } }
    }
    private func save() {
        if let v = Double(text.replacingOccurrences(of: ",", with: ".")), v.isFinite { commit(v) }
        text = format(value)
    }
}
