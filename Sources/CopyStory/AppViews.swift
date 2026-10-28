import AppKit
import SwiftUI
import CopyStoryCore

// Resolve the property-wrapper type explicitly: CLT SDK 27 also declares a
// State macro whose plugin ships only with Xcode. This wrapper works on 26+.
private typealias ViewState<Value> = SwiftUI.State<Value>

private enum PrivacyPolicy {
    static let url = URL(string: "https://copystory.app/privacy/")!
}

// Pinned design: MagicPath 465982269497151488 / revision 465982269497151489.
// Native glass follows the desktop and accessibility settings; CSS blur is not
// a portable AppKit value. Keep these geometry values independent of app state.
enum MainPanelDesign {
    static let size = NSSize(width: 540, height: 716)
    static let radius: CGFloat = 26
    static let accent = Color(red: 0.03, green: 0.49, blue: 1)
    @MainActor static var appIcon: NSImage {
        Bundle.main.url(forResource: "CopyStory", withExtension: "icns")
            .flatMap { NSImage(contentsOf: $0) } ?? NSApp.applicationIconImage ?? NSImage()
    }

    static func frame(in visible: NSRect) -> NSRect {
        let marginX = min(15, max(0, visible.width / 2))
        let marginY = min(18, max(0, visible.height / 2))
        let width = max(0, min(size.width, visible.width - 2 * marginX))
        let height = max(0, min(size.height, visible.height - 2 * marginY))
        let y = min(visible.maxY - marginY - height,
                    max(visible.minY + marginY, visible.midY - height / 2 + 30))
        return NSRect(x: visible.midX - width / 2, y: y, width: width, height: height)
    }
}

// An explicit preview override exercises the fallback without changing macOS
// accessibility preferences. Production leaves this nil and follows the system.
private struct PanelTransparencyOverride: EnvironmentKey {
    static let defaultValue: Bool? = nil
}
extension EnvironmentValues {
    var panelTransparencyOverride: Bool? {
        get { self[PanelTransparencyOverride.self] }
        set { self[PanelTransparencyOverride.self] = newValue }
    }
}

private struct PanelSurface: ViewModifier {
    var radius: CGFloat
    var opacity: Double = 0.16
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.panelTransparencyOverride) private var transparencyOverride
    private var reduceTransparency: Bool { transparencyOverride ?? systemReduceTransparency }
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.background(RoundedRectangle(cornerRadius: radius)
            .fill(reduceTransparency ? Color(nsColor: .controlBackgroundColor) : Color.white.opacity(scheme == .dark ? opacity * 0.55 : opacity)))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(reduceTransparency ? Color(nsColor: .separatorColor) : .white.opacity(scheme == .dark ? 0.18 : 0.35)))
    }
}

private struct PanelKeyHint: View {
    let key: String
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Text(key).font(.system(size: 15)).padding(.horizontal, 5).padding(.vertical, 2)
                .modifier(PanelSurface(radius: 7))
            Text(label).font(.system(size: 12))
        }.foregroundStyle(.secondary).fixedSize()
    }
}

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: LibraryModel
    init(model: AppModel) { self.model = model; library = model.library }
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.panelTransparencyOverride) private var transparencyOverride
    private var reduceTransparency: Bool { transparencyOverride ?? systemReduceTransparency }
    @ViewState private var confirmClear = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            if library.section == .library && library.screen != .browse {
                LibraryDetailView(model: model, library: library)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Image(nsImage: MainPanelDesign.appIcon)
                            .resizable().scaledToFit().frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("CopyStory").font(.system(size: 21, weight: .semibold))
                            Text("A little history. A lot less backtracking.")
                                .font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 0)
                        Button { model.paused.toggle() } label: {
                            Image(systemName: model.paused ? "play.fill" : "pause")
                                .font(.system(size: 18)).frame(width: 39, height: 39)
                                .modifier(PanelSurface(radius: 15))
                        }.buttonStyle(.plain).help(model.paused ? "Resume recording" : "Pause recording")
                            .accessibilityLabel(model.paused ? "Resume recording" : "Pause recording")
                        Menu {
                            Button("Preferences…") { model.openPreferences?() }
                            Button("Clear unpinned history…") { confirmClear = true }.disabled(model.count == 0)
                            Divider()
                            Button("Quit CopyStory") { NSApp.terminate(nil) }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 13))
                                .foregroundStyle(Color(nsColor: .labelColor))
                                .offset(y: -1)
                                .frame(width: 39, height: 39)
                                .contentShape(RoundedRectangle(cornerRadius: 15))
                        }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                        .frame(width: 39, height: 39).modifier(PanelSurface(radius: 15))
                        .accessibilityLabel("History controls")
                    }.padding(.bottom, 18)
                    HStack(spacing: 0) {
                        ForEach(PanelSection.allCases, id: \.self) { section in
                            Button { model.selectSection(section) } label: {
                                Text(section.rawValue).font(.system(size: 15, weight: .medium))
                                    .frame(maxWidth: .infinity).frame(height: 38)
                                    .contentShape(Rectangle())
                                    .background(RoundedRectangle(cornerRadius: 12)
                                        .fill(library.section == section ? (reduceTransparency ? Color(white: scheme == .dark ? 0.28 : 0.88) : Color(nsColor: .controlBackgroundColor).opacity(scheme == .dark ? 0.75 : 0.8)) : .clear))
                            }.buttonStyle(.plain)
                                .accessibilityAddTraits(library.section == section ? .isSelected : [])
                        }
                    }.padding(3).modifier(PanelSurface(radius: 16, opacity: 0.05))
                        .accessibilityElement(children: .contain).accessibilityLabel("Section")
                        .padding(.bottom, 12)
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(.secondary)
                        TextField(library.section == .history ? "Search text or app name" : "Search titles or prompts", text: $model.query)
                            .font(.system(size: 15)).textFieldStyle(.plain).focused($searchFocused)
                            .accessibilityLabel(library.section == .history ? "Search clipboard history" : "Search prompt library")
                        if !model.query.isEmpty {
                            Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.plain).accessibilityLabel("Clear search")
                        }
                        Text("esc").font(.system(size: 12)).foregroundStyle(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2).modifier(PanelSurface(radius: 7, opacity: 0.08))
                    }.padding(.horizontal, 13).frame(height: 46)
                        .modifier(PanelSurface(radius: 15, opacity: 0.07))
                    if library.section == .library {
                        HStack {
                            Picker("Library filter", selection: $library.favoritesOnly) {
                                Text("All").tag(false)
                                Text("Favorites").tag(true)
                            }.pickerStyle(.segmented).frame(width: 190)
                            Spacer()
                            Button("New prompt", systemImage: "plus") { library.edit() }.disabled(library.store == nil)
                        }.padding(.top, 14).padding(.bottom, 20)
                    } else {
                        HStack(spacing: 9) {
                            filterButton(.all, "All", "tray.full")
                            filterButton(.text, "Text", "text.alignleft")
                            filterButton(.images, "Images", "photo")
                            filterButton(.pinned, "Pinned", "pin")
                            Spacer(minLength: 0)
                            Text("\(model.count) items").font(.system(size: 13)).foregroundStyle(.secondary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }.padding(.top, 14).padding(.bottom, 20)
                    }
                }.padding(.horizontal, 20).padding(.top, 22).fixedSize(horizontal: false, vertical: true)
                if library.section == .library {
                    LibraryListView(library: library)
                } else if model.items.isEmpty {
                    emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(model.items) { item in
                                    HistoryRow(item: item, selected: model.selectedID == item.id, model: model)
                                        .id(item.id)
                                        .onTapGesture(count: 2) { model.select(item); model.paste(item) }
                                        .onTapGesture { model.select(item); searchFocused = true }
                                        .contextMenu {
                                            Button("Paste") { model.paste(item) }
                                            Button("Copy") { model.select(item); model.copySelected() }
                                            Button(item.isPinned ? "Unpin" : "Pin") { model.togglePin(item) }
                                            if item.hasText { Button("Save to Library…") { model.saveToLibrary(item) } }
                                            Button("Inspect…") { model.inspectItem?(item) }
                                            Divider()
                                            Button("Delete", role: .destructive) { model.delete(item) }
                                        }
                                }
                                if model.hasMore { Button("Show more history") { model.loadMore() }.buttonStyle(.plain).padding(10) }
                            }.padding(.horizontal, 20).padding(.vertical, 1)
                        }
                        .onChange(of: model.selectedID) { _, id in if let id { proxy.scrollTo(id, anchor: nil) } }
                    }
                }
                if library.section == .history && model.filter == .images {
                    Label("Search images by app or date. Image text isn’t indexed.", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 10)
                }
                if let message = model.captureMessage ?? model.shortcutError {
                    notice(message, symbol: "exclamationmark.triangle")
                }
                if model.capacityBlocked {
                    HStack(alignment: .top) {
                        Image(systemName: "pin.fill")
                        Text("Pinned history fills the limit. Unpin items or increase your storage limit.").font(.caption)
                        Button("Preferences") { model.openPreferences?() }.buttonStyle(.link).font(.caption)
                    }.padding(12).background(.orange.opacity(0.12))
                }
                if !model.accessibilityGranted {
                    HStack(spacing: 8) {
                        Image(systemName: "keyboard")
                        Text("Direct Paste needs event-posting consent and an intended app. Copy remains available.").font(.caption)
                        Spacer(minLength: 0)
                        Button("Set up") { model.openPreferences?() }.font(.caption).buttonStyle(.link)
                    }.foregroundStyle(.secondary).padding(12)
                }
                if let status = model.statusMessage { notice(status, symbol: "info.circle") }
                VStack(spacing: 0) {
                    Rectangle().fill(reduceTransparency ? Color(nsColor: .separatorColor) : .white.opacity(0.25)).frame(height: 1)
                    HStack(spacing: 8) {
                        Circle().fill(model.paused || model.capacityBlocked ? Color.secondary : MainPanelDesign.accent)
                            .frame(width: 11, height: 11).accessibilityHidden(true)
                        Text(model.recordingLabel).font(.system(size: 13)).lineLimit(1)
                        Spacer(minLength: 4)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) {
                                PanelKeyHint(key: "↑↓", label: "Select")
                                PanelKeyHint(key: "↩", label: library.section == .history ? "Paste" : "Open")
                                PanelKeyHint(key: library.section == .history ? "⌘C" : "⌘N", label: library.section == .history ? "Copy" : "New")
                            }
                            Text(library.section == .history ? "↑↓  ↩  ⌘C" : "↑↓  ↩  ⌘N")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                                .accessibilityLabel(library.section == .history ? "Arrow keys select, Return paste, Command C copy" : "Arrow keys select, Return open, Command N new")
                        }
                    }.padding(.top, 15).padding(.bottom, 17)
                }.padding(.horizontal, 20).padding(.top, 12).fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(reduceTransparency ? Color(nsColor: .windowBackgroundColor) :
            (scheme == .dark ? Color.black.opacity(0.18) : Color(red: 0.93, green: 0.92, blue: 0.91).opacity(0.30)))
        .clipShape(RoundedRectangle(cornerRadius: MainPanelDesign.radius))
        .overlay(RoundedRectangle(cornerRadius: MainPanelDesign.radius)
            .strokeBorder(.white.opacity(reduceTransparency ? 0 : scheme == .dark ? 0.30 : 0.75), lineWidth: 1.5))
        .onAppear { searchFocused = true }
        .onChange(of: model.focusRequest) { _, _ in searchFocused = true }
        .onChange(of: library.screen) { _, screen in searchFocused = screen == .browse }
        .alert("Discard unsaved changes?", isPresented: $library.confirmDiscard) {
            Button("Keep editing", role: .cancel) { library.cancelDiscard() }
            Button("Discard", role: .destructive) { library.discardChanges() }
        } message: { Text("Your saved prompts will stay unchanged.") }
        .alert("Delete saved prompt?", isPresented: Binding(get: { library.pendingDelete != nil }, set: { if !$0 { library.pendingDelete = nil } }), presenting: library.pendingDelete) { entry in
            Button("Cancel", role: .cancel) { library.pendingDelete = nil }
            Button("Delete", role: .destructive) {
                library.delete(entry)
                library.pendingDelete = nil
            }
        } message: { _ in Text("This removes the saved template. Completed prompts in history are kept.") }
        .alert("Clear unpinned history?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear history", role: .destructive) { model.clear(includePinned: false) }
        } message: { Text("Pinned items will be kept. Deleted items can’t be recovered through CopyStory.") }
    }

    private func filterButton(_ filter: HistoryFilter, _ title: String, _ symbol: String) -> some View {
        Button { model.filter = filter } label: {
            Text(title).font(.system(size: 14)).padding(.horizontal, 17).frame(height: 35)
                .foregroundStyle(model.filter == filter ? Color.white : Color.primary)
                .background(Capsule().fill(model.filter == filter ? MainPanelDesign.accent : Color.white.opacity(0.12)))
                .overlay(Capsule().strokeBorder(reduceTransparency ? Color(nsColor: .separatorColor) : .white.opacity(0.35)))
        }.buttonStyle(.plain).accessibilityLabel(title)
            .accessibilityAddTraits(model.filter == filter ? .isSelected : [])
    }
    private func notice(_ message: String, symbol: String) -> some View {
        Label(message, systemImage: symbol).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
            .padding(12).background(.quaternary.opacity(0.35))
    }
    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 13) {
            Image(systemName: !model.query.isEmpty ? "magnifyingglass" : model.paused ? "pause.circle" : model.filter == .pinned ? "pin" : "square.on.square")
                .font(.system(size: 38, weight: .light)).foregroundStyle(.secondary)
            Text(!model.query.isEmpty ? "No matching history" : model.paused ? "Recording is paused" : model.filter == .pinned ? "Keep the useful things close" : model.filter == .images ? "Your images will appear here" : "Your next copy starts the story")
                .font(.title3.weight(.semibold))
            Text(!model.query.isEmpty ? "Try a shorter word or a source app’s name." : model.paused ? "Resume recording to remember new text and images." : model.filter == .pinned ? "Pin a snippet or image from its context menu." : "Copy text or an image in any app.\nFind it here whenever you need it.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if model.paused { Button("Resume recording") { model.paused = false }.buttonStyle(.bordered) }
        }.padding(28)
    }
}

private struct HistoryRow: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.panelTransparencyOverride) private var transparencyOverride
    private var reduceTransparency: Bool { transparencyOverride ?? systemReduceTransparency }
    let item: HistoryItem
    let selected: Bool
    @ObservedObject var model: AppModel
    @ViewState private var thumbnail: NSImage?
    var body: some View {
        Button { model.select(item) } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.kind == .image ? "Image, \(item.pixelWidth ?? 0) by \(item.pixelHeight ?? 0) pixels, \(item.sourceApp ?? "unknown app"), \(item.capturedAt.formatted())" : "\(item.preview), \(item.sourceApp ?? "unknown app"), \(item.capturedAt.formatted())")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: "Paste") { model.paste(item) }
        .accessibilityAction(named: "Copy") { model.select(item); model.copySelected() }
        .accessibilityAction(named: item.isPinned ? "Unpin" : "Pin") { model.togglePin(item) }
        .accessibilityActions {
            if item.hasText { Button("Save to Library") { model.saveToLibrary(item) } }
        }
        .accessibilityAction(named: "Inspect") { model.inspectItem?(item) }
        .accessibilityAction(named: "Delete") { model.delete(item) }
        .task(id: item.id) {
            guard item.kind == .image, let url = try? await model.store.thumbnailURL(id: item.id) else { return }
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
            if let data { thumbnail = NSImage(data: data) }
        }
    }
    private var rowContent: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(scheme == .dark ? 0.16 : 0.7))
                if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit().padding(3) }
                else { Image(systemName: item.kind == .image ? "photo" : "text.alignleft").font(.title3).foregroundStyle(.secondary) }
            }.frame(width: 44, height: 44).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                if item.kind == .image {
                    Text(item.preview.isEmpty ? "Image" : item.preview).font(.system(size: 15, weight: .medium)).lineLimit(2)
                } else {
                    Text(verbatim: item.preview).font(.system(size: 15, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                }
                HStack(spacing: 5) {
                    Text(item.sourceApp ?? "Unknown app").lineLimit(1)
                    Text("·")
                    Text(item.capturedAt, style: .relative).lineLimit(1)
                    if item.kind == .image, let w = item.pixelWidth, let h = item.pixelHeight { Text("· \(w) × \(h)") }
                }.font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if item.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary) }
            if selected { Image(systemName: "return").font(.caption).foregroundStyle(MainPanelDesign.accent) }
        }
        .padding(.vertical, 11).padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(
            reduceTransparency ? Color(nsColor: selected ? .unemphasizedSelectedContentBackgroundColor : .controlBackgroundColor) :
                selected ? MainPanelDesign.accent.opacity(scheme == .dark ? 0.25 : 0.17) : Color.white.opacity(scheme == .dark ? 0.10 : 0.23)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? MainPanelDesign.accent.opacity(0.8) : reduceTransparency ? Color(nsColor: .separatorColor) : .white.opacity(0.25)))
        .contentShape(Rectangle())
    }
}

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updates: UpdateService
    @ViewState private var itemLimit = 1000
    @ViewState private var storageLimit = 500
    @ViewState private var clearAll = false
    @ViewState private var clearUnpinned = false
    @ViewState private var applyLimits = false
    @ViewState private var retention = 0
    @ViewState private var applyRetention = false
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("General") {
                    LabeledContent("Open history") {
                        Toggle("Enable global shortcut", isOn: Binding(get: { model.shortcutEnabled }, set: { model.setShortcutEnabled($0) }))
                        Button(model.registeringShortcut ? "Press a shortcut… (Esc cancels)" : model.shortcutLabel) { model.registeringShortcut = true }
                            .help("Default: \(DefaultShortcut.label). Use Command, Control, or Option with a letter, number, or function key.")
                    }
                    Text("Default: \(DefaultShortcut.label) (Option + V). Saved shortcuts are preserved.").font(.caption).foregroundStyle(.secondary)
                    if let error = model.shortcutError { Text(error).font(.caption).foregroundStyle(.orange) }
                    Toggle("Launch at login", isOn: Binding(get: { model.loginEnabled }, set: { model.setLogin($0) }))
                    HStack { Text(model.loginStatus).font(.caption).foregroundStyle(.secondary); Spacer(); Button("Login settings…") { LoginService.openSettings() }.font(.caption) }
                    Toggle("Pause recording", isOn: $model.paused)
                    Text("Appearance follows macOS, including Reduce Transparency and Reduce Motion.").font(.caption).foregroundStyle(.secondary)
                }
                Section("History storage") {
                    LabeledContent("Saved locally", value: "\(model.count) items · \(model.storageLabel)")
                    LabeledContent("Pinned items", value: "\(model.pinnedCount)")
                    HStack {
                        Text("Maximum items")
                        Spacer()
                        TextField("Items", value: $itemLimit, format: .number.grouping(.never)).labelsHidden().accessibilityLabel("Maximum history items").frame(width: 90).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Maximum storage (MB)")
                        Spacer()
                        TextField("Megabytes", value: $storageLimit, format: .number.grouping(.never)).labelsHidden().accessibilityLabel("Maximum storage in megabytes").frame(width: 90).multilineTextAlignment(.trailing)
                    }
                    Text("Oldest unpinned items are removed first. Pinned items count toward both limits; if they fill capacity, new items aren’t saved. Minimum storage: 10 MB.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Apply limits…") { applyLimits = true }.disabled(itemLimit < 1 || itemLimit > 100_000 || storageLimit < 10 || storageLimit > 50_000)
                    Picker("Delete unpinned history after", selection: $retention) {
                        Text("Never").tag(0)
                        Text("1 day").tag(1)
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                    }
                    Text("Pinned items never expire. Expiration runs at startup, when capturing, and every minute while CopyStory is running.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Apply expiration…") { applyRetention = true }.disabled(retention == model.retentionDays)
                    HStack {
                        Button("Clear unpinned…") { clearUnpinned = true }
                        Button("Clear all history…", role: .destructive) { clearAll = true }
                    }
                }
                Section("Privacy & permissions") {
                    Text("Excluded apps").font(.headline)
                    ForEach(model.excludedAppBundleIDs, id: \.self) { bundleID in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(model.excludedAppName(bundleID))
                                Text(bundleID).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove") { model.setExcludedApps(model.excludedAppBundleIDs.filter { $0 != bundleID }) }
                                .accessibilityLabel("Stop excluding \(model.excludedAppName(bundleID))")
                        }
                    }
                    Button("Exclude app…") { model.chooseExcludedApps() }
                    Text("Skips future copies while these apps are frontmost. Existing history is kept. Browser extensions and background apps may not be identifiable; pause recording before copying secrets.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Respect confidential clipboard markers", isOn: $model.respectConfidential)
                    Text("Ordinary copied passwords, keys, and other secrets can still enter history. History is stored on this Mac without app-level encryption. Pause before copying sensitive material.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Enable experimental Direct Paste", isOn: Binding(get: { model.directPasteEnabled }, set: { model.setDirectPasteEnabled($0) }))
                    LabeledContent("Event-posting access", value: model.accessibilityGranted ? "Available at last check" : "Unavailable or not yet granted")
                    #if COPYSTORY_DEVELOPMENT
                    Button("Check readiness") { model.checkReadiness() }
                    if model.readinessCheck.status != .idle {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(ReadinessCheck.identity()).font(.caption.monospaced())
                            if let sample = model.readinessCheck.initial {
                                Text("Initial\n" + ReadinessCheck.describe(sample))
                            }
                            if let sample = model.readinessCheck.next {
                                Text("Next normal refresh\n" + ReadinessCheck.describe(sample))
                            }
                            Text(model.readinessCheck.status == .waiting
                                 ? "Waiting for the next normal refresh (up to 5 seconds)…"
                                 : model.readinessCheck.status == .complete
                                 ? "Complete · recording stopped."
                                 : "Stale · no timely next refresh; recording stopped.")
                            Text("Read-only, current process only. Native calls are sequential, not atomic. AX trust does not authorize Paste. This report does not explain an earlier build’s runtime.")
                                .foregroundStyle(.secondary)
                            Button("Dismiss readiness report") { model.dismissReadinessCheck() }
                        }.font(.caption).textSelection(.enabled)
                    }
                    #endif
                    Button("Request event-posting access…") {
                        PasteCoordinator.requestPostingConsent()
                        model.refreshPostingReadiness()
                    }
                    if !model.accessibilityGranted {
                        Text("macOS currently reports event-posting access unavailable. In System Settings → Privacy & Security → Accessibility, inspect the exact CopyStory app you intend to use. A visible enabled row does not prove effective access. Copy remains available.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Paste requests ⌘V once in the intended app’s current focus. It never restores the original field or retries. macOS and the destination control insertion; permission, focus and posting cannot be checked atomically. Secure input reported by macOS cancels the request, but other protected or unsupported controls cannot always be identified. Use Copy if nothing appears.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Clipboard recording permission is separate from event-posting access. Requesting access does not mean macOS granted it. Recording and explicit Copy do not require event-posting access.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Clipboard settings…") { ClipboardMonitor.openClipboardSettings() }
                    if let message = model.captureMessage { Text(message).font(.caption).foregroundStyle(.orange) }
                }
                if !AppDistribution.isAppStore {
                    Section("Updates") {
                        Toggle("Automatically check for updates", isOn: Binding(get: { updates.automaticallyChecks }, set: { updates.setAutomaticallyChecks($0) }))
                            .disabled(!updates.isAvailable)
                        Toggle("Automatically download and install updates", isOn: Binding(get: { updates.automaticallyDownloads }, set: { updates.setAutomaticallyDownloads($0) }))
                            .disabled(!updates.isAvailable || !updates.automaticallyChecks)
                        Button("Check for Updates…") { updates.checkForUpdates() }.disabled(!updates.canCheckForUpdates)
                        Text("Checks connect to GitHub. Updates are verified before installation. Clipboard history is never sent; system profiling is disabled.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let reason = updates.unavailableReason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Section("About CopyStory") {
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development") · MIT License").font(.callout)
                    Text(AppDistribution.isAppStore ? "History stays on this Mac. No accounts or analytics." : "History stays on this Mac. No accounts or analytics. Optional updates use GitHub.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Privacy Policy") {
                            NSWorkspace.shared.open(PrivacyPolicy.url)
                        }
                        .help("Open the privacy policy in your default browser")
                        .accessibilityHint("Opens in your default browser")
                        Button("View source code") {
                            NSWorkspace.shared.open(UpdatePolicy.sourceURL)
                        }
                        Button("Open storage folder") {
                            NSWorkspace.shared.open(model.storageDirectory)
                        }
                    }
                }
            }.formStyle(.grouped)
            if let status = model.statusMessage { Text(status).font(.caption).foregroundStyle(.secondary).padding(12) }
        }
        .frame(width: 570, height: 720)
        .onDisappear {
            #if COPYSTORY_DEVELOPMENT
            model.dismissReadinessCheck()
            #endif
        }
        .onAppear { itemLimit = model.maxItems; storageLimit = model.maxMB; retention = model.retentionDays }
        .alert("Apply history expiration?", isPresented: $applyRetention) {
            Button("Cancel", role: .cancel) {}
            Button("Apply", role: retention == 0 ? nil : .destructive) { model.applyRetention(days: retention) }
        } message: {
            Text(retention == 0 ? "Automatic age-based deletion will stop. Previously deleted items cannot be restored." : "Unpinned items older than \(retention) days will be deleted now and automatically in the future. This cannot be undone. Pinned items are kept.")
        }
        .alert("Clear all history?", isPresented: $clearAll) {
            Button("Cancel", role: .cancel) {}
            Button("Delete everything", role: .destructive) { model.clear(includePinned: true) }
        } message: { Text("This deletes pinned items too. It can’t be undone. CopyStory does not promise forensic secure erasure.") }
        .alert("Clear unpinned history?", isPresented: $clearUnpinned) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { model.clear(includePinned: false) }
        } message: { Text("Pinned items will be kept. This can’t be undone.") }
        .alert("Apply these history limits?", isPresented: $applyLimits) {
            Button("Cancel", role: .cancel) {}
            Button("Apply") { model.applyLimits(items: itemLimit, megabytes: storageLimit) }
        } message: { Text("CopyStory may immediately delete older unpinned items to meet these limits. Pinned items are always kept.") }
    }
}

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var onFinish: (Bool, Bool) -> Void
    @ViewState private var loginWasChanged = false
    @ViewState private var login = OnboardingDefaults.launchAtLogin
    init(model: AppModel, onFinish: @escaping (Bool, Bool) -> Void) {
        self.model = model; self.onFinish = onFinish
        _login = ViewState(initialValue: OnboardingDefaults.initialLogin(existingRegistration: model.loginEnabled))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "square.on.square").font(.system(size: 40, weight: .light)).foregroundStyle(.tint)
                .frame(width: 76, height: 76).glassEffect(.regular, in: .rect(cornerRadius: 22))
            VStack(alignment: .leading, spacing: 8) {
                Text("A home for what you copy.").font(.system(size: 28, weight: .semibold))
                Text("CopyStory remembers text and images, so your next thought doesn’t replace your last one.").font(.title3).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 18) {
                onboardingRow("keyboard", model.shortcutEnabled ? "One shortcut away" : "Open from the menu bar",
                    model.shortcutEnabled
                        ? "Press \(model.shortcutLabel) to open or close History, or choose Open CopyStory from the menu bar. Use ↑↓ and Return to reuse an item; ⌘C copies it."
                        : "Choose Open CopyStory from the menu bar. Your shortcut is \(model.shortcutLabel); enable it in Preferences when ready. Use ↑↓ and Return to reuse an item; ⌘C copies it.")
                onboardingRow("internaldrive", "Saved on this Mac", "macOS may ask to read the clipboard. History survives restarts: up to 1,000 items or 500 MB. Pinned items are protected.")
                onboardingRow("hand.raised", "You decide what stays", "Unmarked passwords and API keys can enter history. Storage isn’t encrypted by the app. Pause recording or clear history from the menu.")
                onboardingRow("cursorarrow.click", "Reuse your clipboard", "Experimental Direct Paste is opt-in in Preferences and requires separate event-posting access. It requests insertion once; insertion is not confirmed. Explicit Copy remains available.")
            }
            Toggle("Launch CopyStory at login", isOn: $login)
                .onChange(of: login) { _, _ in loginWasChanged = true }
            HStack {
                Text("No accounts. No uploads. Just your history.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Start remembering") { onFinish(login, loginWasChanged) }.buttonStyle(.borderedProminent).controlSize(.large)
            }
        }.padding(32).frame(width: 580)
    }
    private func onboardingRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(.tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline); Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

struct InspectView: View {
    let item: HistoryItem
    let store: HistoryStore
    @ViewState private var text: String?
    @ViewState private var image: NSImage?
    @ViewState private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(item.kind == .image ? "Image" : "Text", systemImage: item.kind == .image ? "photo" : "text.alignleft").font(.headline)
                Spacer()
                Text(item.sourceApp ?? "Unknown app").foregroundStyle(.secondary)
                Text(item.capturedAt.formatted()).foregroundStyle(.secondary)
            }.font(.caption)
            Divider()
            if let image { ScrollView([.horizontal, .vertical]) { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 720, maxHeight: 560) } }
            if let text { ReadOnlyTextView(text: text).frame(maxWidth: .infinity, maxHeight: .infinity) }
            if let error { ContentUnavailableView(error, systemImage: "exclamationmark.triangle") }
            if text == nil && image == nil && error == nil { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.padding(20).frame(minWidth: 640, minHeight: 430)
            .task {
                do {
                    let payload = try await store.payload(id: item.id)
                    text = payload.text
                    if let data = payload.imageData { image = NSImage(data: data) }
                } catch { self.error = "This item’s content is unavailable." }
            }
    }
}

private struct ReadOnlyTextView: NSViewRepresentable {
    let text: String
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.drawsBackground = false
        view.textContainerInset = NSSize(width: 8, height: 8)
        view.autoresizingMask = [.width]
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) { (view.documentView as? NSTextView)?.string = text }
}
