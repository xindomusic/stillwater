import SwiftUI
import AppKit
import SpriteKit

// Explicit wrapper alias also supports command-line SDKs without SwiftUI's new State macro plugin.
private typealias ViewState<Value> = SwiftUI.State<Value>

private enum Palette {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(rgb: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        })
    }
    static let background = adaptive(0xf3f5f8, 0x101318)
    static let sidebar = adaptive(0xffffff, 0x171b22)
    static let card = adaptive(0xffffff, 0x1b2028)
    static let border = adaptive(0xdfe4ec, 0x303743)
    static let accent = adaptive(0x3268d2, 0x8db9ff)
    static let muted = adaptive(0x637083, 0x9aa7b8)
    static let text = adaptive(0x162130, 0xeaf0f7)
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case aquarium = "My aquarium", scenes = "Scenes", fish = "Fish & friends", motion = "Motion & light"
    var id: String { rawValue }
    var icon: String {
        switch self { case .aquarium: return "water.waves"; case .scenes: return "square.stack.3d.up"; case .fish: return "fish"; case .motion: return "slider.horizontal.3" }
    }
}

struct AquariumPreview: NSViewRepresentable {
    var configuration: AquariumConfiguration
    func makeNSView(context: Context) -> AquariumSurface {
        AquariumSurface(frame: CGRect(x: 0, y: 0, width: 800, height: 450), configuration: configuration)
    }
    func updateNSView(_ view: AquariumSurface, context: Context) {
        if view.aquarium.configuration != configuration { view.apply(configuration) }
    }
    static func dismantleNSView(_ view: AquariumSurface, coordinator: ()) { view.isPaused = true }
}

struct SettingsView: View {
    @ObservedObject var store: AquariumStore
    var previewAction: () -> Void
    var exportAction: () -> Void
    var desktopStillAction: () -> Void
    var reviewPreview: NSImage? = nil
    var reviewSection: SettingsSection? = nil
    var reviewResidentFilter: String? = nil
    @ViewState private var section: SettingsSection = .aquarium
    @ViewState private var showReset = false

    private var config: AquariumConfiguration { store.configuration }
    private var activeSection: SettingsSection { reviewSection ?? section }
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Palette.border).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch activeSection {
                        case .aquarium: overview
                        case .scenes: scenesPanel
                        case .fish: fishPanel
                        case .motion: motionPanel
                        }
                    }.padding(.horizontal, 32).padding(.top, 8).padding(.bottom, 28)
                }
                footer
            }
        }
        .background(Palette.background)
        .foregroundStyle(Palette.text)
        .tint(Palette.accent)
        .frame(minWidth: 1000, minHeight: 750)
        .onAppear { if let filter = reviewResidentFilter { residentFilter = filter } }
        .alert("Reset your aquarium?", isPresented: $showReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) { store.restoreDefaults() }
        } message: { Text("Restore Riverlight, its original fish population, and gentle motion settings.") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "fish.fill").font(.system(size: 27, weight: .light)).foregroundStyle(Palette.accent)
                Text("Stillwater").font(.system(size: 25, weight: .medium)).tracking(-0.7)
            }.padding(.top, 42).padding(.bottom, 8)
            Text("YOUR QUIET CORNER")
                .font(.system(size: 8.5, weight: .semibold)).tracking(1.5).foregroundStyle(Palette.muted)
            VStack(spacing: 6) {
                ForEach(SettingsSection.allCases) { item in
                    Button { section = item } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon).font(.system(size: 16)).frame(width: 22)
                            Text(item == .fish ? "Residents" : item.rawValue).font(.system(size: 13, weight: activeSection == item ? .semibold : .regular)).lineLimit(1)
                            Spacer()
                            if item == .fish { Text("\(config.totalFish)").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(Palette.muted) }
                        }
                        .foregroundStyle(activeSection == item ? Palette.accent : Palette.muted)
                        .padding(.horizontal, 13).padding(.vertical, 13)
                        .background(activeSection == item ? Palette.accent.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.padding(.top, 42)
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "leaf").foregroundStyle(Palette.accent).font(.system(size: 19))
                Text("Room to\nbreathe.").font(.system(size: 22, weight: .regular)).lineSpacing(3)
                Text("Your aquarium remembers\njust how you like it.").font(.system(size: 11)).lineSpacing(4).foregroundStyle(Palette.muted)
            }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
            Button { showReset = true } label: {
                Label("Restore defaults", systemImage: "arrow.counterclockwise").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }.buttonStyle(.plain).padding(.top, 22).padding(.bottom, 22)
        }.padding(.horizontal, 20).frame(width: 230).background(Palette.sidebar)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 7) {
                Text("YOUR PERSONAL AQUARIUM").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(Palette.muted)
                Text(activeSection == .aquarium ? "A calmer desktop." : activeSection.rawValue)
                    .font(.system(size: 31, weight: .regular)).tracking(-0.8)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(config.mode == .live ? Palette.accent : Palette.muted).frame(width: 5, height: 5)
                Text(config.mode == .live ? "LIVE" : "STILL").font(.system(size: 9, weight: .semibold)).tracking(1.4)
            }.foregroundStyle(Palette.accent).padding(.horizontal, 12).padding(.vertical, 8)
                .background(Palette.accent.opacity(0.07), in: Capsule()).overlay(Capsule().stroke(Palette.accent.opacity(0.17)))
        }.padding(.horizontal, 32).padding(.top, 31).padding(.bottom, 24)
    }

    private var overview: some View {
        Group {
            ZStack(alignment: .bottomLeading) {
                if let reviewPreview {
                    Image(nsImage: reviewPreview).resizable().aspectRatio(contentMode: .fill)
                } else {
                    AquariumPreview(configuration: config)
                }
                LinearGradient(colors: [.clear, .black.opacity(0.68)], startPoint: .center, endPoint: .bottom).allowsHitTesting(false)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(config.theme.tag).font(.system(size: 8, weight: .semibold)).tracking(1.8).foregroundStyle(.white.opacity(0.65))
                        Text(config.theme.title).font(.system(size: 27, weight: .regular))
                        Text("\(config.totalFish) fish · Asian freshwater").font(.system(size: 11)).foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer()
                    Button { store.requestFeed() } label: {
                        HStack(spacing: 8) {
                            Label("Feed fish", systemImage: "circle.dotted")
                            Text(store.feedingShortcutAvailable ? FeedingShortcut.label : "⌘F").foregroundStyle(.white.opacity(0.65))
                        }.font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 13).padding(.vertical, 11).background(.white.opacity(0.12), in: Capsule())
                    }.buttonStyle(.plain).disabled(!store.canFeed)
                        .help("Feed fish: ⌘F in Stillwater, or Control–Option–Command–F from any app when enabled. Requires Live mode and swimming.")
                    Button(action: previewAction) { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 13)).padding(12).background(.white.opacity(0.12), in: Circle()) }
                        .buttonStyle(.plain).help("Open a larger aquarium preview").accessibilityLabel("Open larger preview")
                }.padding(25).foregroundStyle(.white)
            }.aspectRatio(16.0 / 9.0, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.border))
            HStack(spacing: 12) {
                modeCard(.live, icon: "water.waves", title: "Let it live", detail: "A little life in the background")
                modeCard(.still, icon: "photo", title: "Keep it still", detail: "Freeze this moment. All motion stops.")
            }
            lightingControls
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Find your favorite corner of the water.").font(.system(size: 14, weight: .medium))
                    Text("Three scenes, ten species, endless quiet moments.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Button { section = .scenes } label: { HStack(spacing: 8) { Text("Explore scenes"); Image(systemName: "arrow.right") }.font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent) }.buttonStyle(.plain)
            }.padding(.vertical, 3)
        }
    }

    private func modeCard(_ mode: AquariumMode, icon: String, title: String, detail: String) -> some View {
        Button {
            var next = config; next.mode = mode
            if mode == .live { next.wallpaperEnabled = true }
            store.configuration = next
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 19)).foregroundStyle(config.mode == mode ? Palette.accent : Palette.muted)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    Text(detail).font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 4)
                Image(systemName: config.mode == mode ? "checkmark.circle.fill" : "circle").foregroundStyle(config.mode == mode ? Palette.accent : Palette.muted.opacity(0.6)).font(.system(size: 15))
            }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
                .background(config.mode == mode ? Palette.accent.opacity(0.06) : Palette.card, in: RoundedRectangle(cornerRadius: 11))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(config.mode == mode ? Palette.accent.opacity(0.32) : Palette.border))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(mode == .live ? "Live aquarium mode" : "Still image mode")
    }

    private var scenesPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("A change of scenery, at your own pace.").font(.system(size: 13)).foregroundStyle(Palette.muted)
            ForEach(AquariumTheme.allCases) { theme in
                Button { store.configuration.theme = theme } label: {
                    HStack(spacing: 22) {
                        Image(nsImage: Artwork.image(theme)).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 250, height: 135).clipped().clipShape(RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 10) {
                            Text(theme.tag).font(.system(size: 8, weight: .semibold)).tracking(1.6).foregroundStyle(Palette.muted)
                            Text(theme.title).font(.system(size: 23, weight: .regular))
                            Text(theme.subtitle).font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: config.theme == theme ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(config.theme == theme ? Palette.accent : Palette.muted.opacity(0.5)).font(.system(size: 20))
                    }.padding(13).background(config.theme == theme ? Palette.accent.opacity(0.055) : Palette.card, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(config.theme == theme ? Palette.accent.opacity(0.32) : Palette.border))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Select \(theme.title)")
            }
            Text("Your fish and motion settings stay with you when you change scenes.").font(.system(size: 11)).foregroundStyle(Palette.muted).padding(.top, 3)
        }
    }

    @ViewState private var residentFilter = "All"
    private let residentFilters = ["All", "Small fish", "Larger fish", "Shrimp & crabs"]
    private var visibleSpecies: [FishSpecies] {
        FishSpecies.allCases.filter { species in
            switch residentFilter {
            case "Small fish": return !species.isInvertebrate && species.bodySize < 90
            case "Larger fish": return !species.isInvertebrate && species.bodySize >= 90
            case "Shrimp & crabs": return species.isInvertebrate
            default: return true
            }
        }
    }
    private var fishPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Meet your little residents.").font(.system(size: 15, weight: .regular))
                Spacer()
                Text("\(config.totalFish) RESIDENTS IN TOTAL").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(Palette.accent)
            }
            Picker("Residents", selection: $residentFilter) {
                ForEach(residentFilters, id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)
            ForEach(visibleSpecies) { species in
                HStack(spacing: 20) {
                    Image(nsImage: Artwork.fishImage(species)).resizable().aspectRatio(contentMode: .fit).frame(width: 110, height: 95)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(species.name).font(.system(size: 19, weight: .regular))
                        Text(species.detail).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    HStack(spacing: 0) {
                        countButton(species, delta: -1)
                        Text("\(config.count(species))").font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit().frame(width: 44)
                        countButton(species, delta: 1)
                    }.padding(5).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }.padding(.horizontal, 21).padding(.vertical, 5).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border))
            }
            HStack(spacing: 12) {
                populationButton("A quiet few", counts: [6, 4, 1, 2])
                populationButton("A lively community", counts: [12, 8, 2, 4])
                populationButton("Just the plants", counts: [0, 0, 0, 0])
            }.padding(.top, 3)
            HStack(spacing: 12) {
                populationButton("Colorful mix", counts: [5, 3, 1, 2, 5, 3, 1, 1, 4, 2])
                populationButton("Bottom garden", counts: [0, 0, 0, 2, 0, 0, 0, 0, 8, 4])
            }
            Text("Up to 30 of each species, 120 residents in total. Changes appear immediately.").font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
    }

    private func countButton(_ species: FishSpecies, delta: Int) -> some View {
        Button { store.configuration.setCount(species, config.count(species) + delta) } label: {
            Image(systemName: delta < 0 ? "minus" : "plus").font(.system(size: 12, weight: .medium)).frame(width: 28, height: 30).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(Palette.accent)
            .disabled(delta < 0 ? config.count(species) == 0 : config.count(species) == 30 || config.totalFish >= AquariumConfiguration.populationLimit)
            .accessibilityLabel("\(delta < 0 ? "Remove" : "Add") one \(species.name)")
    }
    private func populationButton(_ title: String, counts: [Int]) -> some View {
        Button {
            var next = config
            for species in FishSpecies.allCases { next.setCount(species, 0) }
            for (i, species) in FishSpecies.allCases.enumerated() { next.setCount(species, counts.indices.contains(i) ? counts[i] : 0) }
            store.configuration = next
        } label: { Text(title).font(.system(size: 11)).padding(.horizontal, 14).padding(.vertical, 10).background(Palette.card, in: Capsule()).overlay(Capsule().stroke(Palette.border)) }
            .buttonStyle(.plain)
    }

    private var motionPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                modeCard(.live, icon: "water.waves", title: "Live aquarium", detail: "Gentle, continuous movement")
                modeCard(.still, icon: "photo", title: "Still image", detail: "Freeze fish, plants, and water")
            }
            lightingControls
            VStack(spacing: 22) {
                sliderRow("Swimming speed", detail: "From a gentle drift to a lively swim", value: $store.configuration.swimmingSpeed, range: 0...2, display: String(format: "%.1f×", config.swimmingSpeed), icon: "fish")
                sliderRow("Plant sway", detail: "A soft current through the leaves", value: $store.configuration.plantSway, range: 0...1, display: "\(Int(config.plantSway * 100))%", icon: "leaf")
                sliderRow("Water movement", detail: "Surface ripples and drifting underwater light", value: $store.configuration.shimmer, range: 0...1, display: "\(Int(config.shimmer * 100))%", icon: "sparkles")
                sliderRow("Brightness", detail: "Set the mood for your desktop", value: $store.configuration.brightness, range: 0.4...1.3, display: "\(Int(config.brightness * 100))%", icon: "sun.max")
            }.padding(23).background(Palette.card, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(Palette.border))
            VStack(alignment: .leading, spacing: 7) {
                Toggle("Feed from any app · ⌃⌥⌘F", isOn: Binding(get: { config.usesGlobalFeedingShortcut }, set: { store.configuration.feedingShortcutEnabled = $0 }))
                    .toggleStyle(.switch).font(.system(size: 12))
                Text(config.usesGlobalFeedingShortcut && !store.feedingShortcutAvailable
                     ? "Shortcut unavailable. Use Feed fish or ⌘F while Stillwater is active."
                     : "A small portion of food, without opening settings. ⌘F also works in Stillwater.")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted)
            }.padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 11))
            HStack(spacing: 25) {
                Toggle("Bubbles", isOn: $store.configuration.bubbles)
                Toggle("Drifting particles", isOn: $store.configuration.particles)
            }.toggleStyle(.switch).font(.system(size: 12))
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Animation quality").font(.system(size: 12, weight: .medium))
                    Text("Still mode stops the animation loop.").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Picker("Animation quality", selection: $store.configuration.quality) {
                    ForEach(RenderQuality.allCases) { quality in Text(quality.title).tag(quality) }
                }.labelsHidden().frame(width: 185)
            }.padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 11))
        }
    }

    private var lightingControls: some View {
        HStack(spacing: 18) {
            Image(systemName: "circle.lefthalf.filled").font(.system(size: 19)).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text("Day & night").font(.system(size: 12, weight: .semibold))
                Text("Follow your Mac’s Light or Dark appearance.").font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            Picker("Aquarium lighting", selection: Binding(get: { config.lightingMode }, set: { store.configuration.lighting = $0 })) {
                ForEach(AquariumLighting.allCases) { lighting in Text(lighting.title).tag(lighting) }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 240)
                .help("Follow Mac switches with macOS appearance, including its automatic schedule. Day and Night override aquarium lighting only.")
        }.padding(18).background(Palette.card, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Palette.border))
    }

    private func sliderRow(_ title: String, detail: String, value: Binding<Double>, range: ClosedRange<Double>, display: String, icon: String) -> some View {
        HStack(spacing: 15) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(Palette.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 10)).foregroundStyle(Palette.muted)
            }.frame(width: 225, alignment: .leading)
            Slider(value: value, in: range).accessibilityLabel(title)
            Text(display).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.accent).frame(width: 48, alignment: .trailing)
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.border).frame(height: 1)
            HStack(spacing: 14) {
                Toggle("On desktop", isOn: $store.configuration.wallpaperEnabled).toggleStyle(.switch).font(.system(size: 11))
                Menu {
                    Button("All displays") { store.configuration.allDisplays = true }
                    Button("Main display only") { store.configuration.allDisplays = false }
                } label: { Label(config.allDisplays ? "All displays" : "Main display", systemImage: "display").font(.system(size: 10)) }.menuStyle(.borderlessButton).fixedSize()
                Spacer()
                Menu {
                    Button("Save aquarium as PNG…", action: exportAction)
                    Button("Set as macOS still wallpaper", action: desktopStillAction)
                } label: { Label("Save a moment", systemImage: "square.and.arrow.up").font(.system(size: 11, weight: .medium)) }.menuStyle(.borderlessButton).fixedSize()
            }.padding(.horizontal, 26).padding(.vertical, 16)
            if let message = store.message {
                HStack {
                    Text(message).font(.system(size: 10)).foregroundStyle(Palette.accent)
                    Spacer()
                    Button { store.message = nil } label: { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.plain)
                }.padding(.horizontal, 26).padding(.bottom, 12)
            }
        }
    }
}
