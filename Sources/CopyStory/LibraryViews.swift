import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CopyStoryCore

struct LibraryListView: View {
    @ObservedObject var library: LibraryModel
    var onSelect: () -> Void = {}
    var body: some View {
        VStack(spacing: 0) {
            if let error = library.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout).padding()
            }
            if library.canStartExample {
                ContentUnavailableView {
                    Label("Your reusable templates", systemImage: "text.book.closed")
                } description: {
                    Text("Try a follow-up with a fill-in name, or create a template of your own.")
                } actions: {
                    Button("Try an example") { library.startExample() }
                        .buttonStyle(.bordered)
                }
            } else if library.items.isEmpty {
                ContentUnavailableView(library.searching ? "Searching…" : library.query.isEmpty ? (library.favoritesOnly ? "No favorites yet" : "Your reusable templates") : "No matching templates",
                    systemImage: "text.book.closed",
                    description: Text(library.query.isEmpty ? "Save text from history or create a template with {{variables}}." : "Try a word from the title or template text."))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(library.items) { entry in
                                row(entry).id(entry.id)
                            }
                            if library.hasMore { Button("Show more templates") { library.loadMore() }.padding() }
                        }.padding(10)
                    }
                    .onChange(of: library.selectedID) { _, id in if let id { proxy.scrollTo(id) } }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func row(_ entry: LibraryEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.images.isEmpty ? "text.alignleft" : "photo.on.rectangle").font(.title2).foregroundStyle(.secondary).frame(width: 40)
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: entry.title).font(.headline).lineLimit(1)
                Text(verbatim: entry.template).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                Text(entry.images.isEmpty ? (entry.variables.isEmpty ? "Text snippet" : entry.variables.count == 1 ? "1 variable" : "\(entry.variables.count) variables") : (entry.images.count == 1 ? "Text + 1 image" : "Text + \(entry.images.count) images")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button { library.toggleFavorite(entry) } label: {
                Image(systemName: entry.isFavorite ? "star.fill" : "star").foregroundStyle(entry.isFavorite ? Color.accentColor : .secondary)
            }.buttonStyle(.borderless).accessibilityLabel(entry.isFavorite ? "Remove \(entry.title) from favorites" : "Favorite \(entry.title)")
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(library.selectedID == entry.id ? Color.accentColor.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(library.selectedID == entry.id ? Color.accentColor.opacity(0.45) : .clear))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { library.selectedID = entry.id; library.open(entry) }
        .onTapGesture { library.selectedID = entry.id; onSelect() }
        .contextMenu {
            Button("Use template") { library.open(entry) }
            Button("Edit…") { library.edit(entry) }
            Button(entry.isFavorite ? "Remove favorite" : "Favorite") { library.toggleFavorite(entry) }
            Divider()
            Button("Delete…", role: .destructive) { library.pendingDelete = entry }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(entry.title), \(entry.variables.count) \(entry.variables.count == 1 ? "variable" : "variables")\(entry.isFavorite ? ", favorite" : "")"))
        .accessibilityHint(!entry.images.isEmpty ? "Open to copy text and \(entry.images.count) images together or one part at a time." : AppDistribution.directPasteAvailable ? "Open to fill in variables, copy, or paste." : "Open to fill in variables and copy.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { library.open(entry) }
        .accessibilityAction(named: entry.isFavorite ? "Remove favorite" : "Favorite") { library.toggleFavorite(entry) }
        .accessibilityAddTraits(library.selectedID == entry.id ? .isSelected : [])
        .accessibilityAction(named: "Use template") { library.open(entry) }
        .accessibilityAction(named: "Edit") { library.edit(entry) }
        .accessibilityAction(named: "Delete") { library.pendingDelete = entry }
    }
}

struct LibraryDetailView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: LibraryModel
    var onSelect: () -> Void = {}
    @FocusState private var focusedField: String?
    @State private var addingImage = false
    @State private var nextPart = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Back", systemImage: "chevron.left") { library.back() }.disabled(library.saving || model.busy)
                Spacer()
                Text(library.screen == .editor ? "Edit template" : library.useEntry?.title ?? "Use template").font(.headline).lineLimit(1)
                Spacer()
                if library.screen == .editor {
                    Button(library.saving ? "Saving…" : "Save") { library.saveDraft() }
                        .buttonStyle(.borderedProminent).disabled(library.draftError != nil || library.saving)
                }
            }.padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if library.screen == .editor { editor }
                    else { useForm }
                    if let error = library.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red)
                    }
                }.padding(20)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if library.screen == .use {
                Divider()
                HStack {
                    if let message = model.statusMessage { Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                    Spacer()
                    if let entry = library.useEntry, !entry.images.isEmpty {
                        if nextPart <= entry.images.count {
                            Button("Copy next (\(nextPart + 1)/\(entry.images.count + 1))") {
                                if model.copyMixedTemplate(step: nextPart) { nextPart += 1 }
                            }.disabled(!canUse)
                        }
                        if nextPart > 0 { Button("Reset") { nextPart = 0 } }
                        Button("Copy together") { if model.copyMixedTemplate() { nextPart = 0 } }
                            .buttonStyle(.borderedProminent).disabled(!canUse)
                    } else {
                    #if COPYSTORY_PRODUCTION && !COPYSTORY_TESTFLIGHT_DIRECT_PASTE
                    Button("Copy  ⌘↩") { model.usePrompt(copyOnly: true) }.buttonStyle(.borderedProminent).disabled(!canUse)
                    #else
                    Button("Copy") { model.usePrompt(copyOnly: true) }.disabled(!canUse)
                    Button("Paste  ⌘↩") { model.usePrompt(copyOnly: false) }.buttonStyle(.borderedProminent).disabled(!canUse)
                    #endif
                    }
                }.padding(16)
            }
        }
        .fileImporter(isPresented: $addingImage, allowedContentTypes: [.png]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let file = try FileHandle(forReadingFrom: url)
                defer { try? file.close() }
                let limit = TemplateImage.maximumTotalBytes
                guard let data = try file.read(upToCount: limit + 1), data.count <= limit,
                      var draft = library.draft,
                      draft.images.reduce(data.count, { $0 + $1.png.count }) <= limit,
                      draft.images.count < TemplateImage.maximumCount else { throw TemplateError.invalidImages }
                draft.images.append(try TemplateImage(label: url.deletingPathExtension().lastPathComponent, png: data))
                library.draft = draft
                library.errorMessage = nil
            } catch { library.errorMessage = "Couldn’t add image. \(error.localizedDescription)" }
        }
        .onChange(of: library.values) { _, _ in nextPart = 0 }
        .task(id: library.screen) {
            nextPart = 0
            await Task.yield()
            focusedField = library.screen == .editor ? "title" : library.useEntry?.variables.first?.name
        }
    }
    private var canUse: Bool {
        if case .success = library.rendered { return !model.busy }
        return false
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Title").font(.headline)
                TextField("Name this template", text: Binding(get: { library.draft?.title ?? "" }, set: { library.draft?.title = $0 }))
                    .textFieldStyle(.roundedBorder).focused($focusedField, equals: "title").accessibilityLabel("Template title")
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Template").font(.headline)
                PromptTextEditor(text: Binding(get: { library.draft?.template ?? "" }, set: { library.setTemplate($0) }), label: "Template text", monospaced: true)
                    .frame(minHeight: 140)
                Text(verbatim: "Add {{name}} to create a variable. Use \\{{name}} for literal braces.").font(.caption).foregroundStyle(.secondary)
            }
            if let draft = library.draft, !draft.variables.isEmpty {
                Text("Variables & saved defaults").font(.headline)
                ForEach(draft.variables) { variable in
                    VariableEditor(variable: Binding(get: { library.draft?.variables.first { $0.name == variable.name } ?? variable }, set: { value in
                        if let index = library.draft?.variables.firstIndex(where: { $0.name == variable.name }) { library.draft?.variables[index] = value }
                    }))
                }
            }
            if let entry = library.draft {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Images").font(.headline)
                    Text("PNG images are saved with this template and copied after the text, in the order shown.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(entry.images.enumerated()), id: \.element.id) { index, image in
                        HStack {
                            Text("\(index + 1). \(image.label)").lineLimit(1)
                            Spacer()
                            Button("Move image up", systemImage: "arrow.up") {
                                library.draft?.images.swapAt(index, index - 1)
                            }.labelStyle(.iconOnly).disabled(index == 0)
                            Button("Remove image", systemImage: "xmark") {
                                library.draft?.images.removeAll { $0.id == image.id }
                            }.labelStyle(.iconOnly)
                        }
                    }
                    Button("Add PNG image", systemImage: "plus") { addingImage = true }
                        .disabled(entry.images.count >= TemplateImage.maximumCount)
                }
            }
            if let error = library.draftError { Text(error).font(.caption).foregroundStyle(.secondary) }
        }.disabled(library.saving)
    }
    private var useForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let entry = library.useEntry {
                ForEach(entry.variables) { variable in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(variable.name).font(.headline)
                        let value = Binding(get: { library.values[variable.name] ?? "" }, set: { library.values[variable.name] = $0 })
                        if variable.kind == .dropdown {
                            Picker(variable.name, selection: value) {
                                ForEach(variable.options, id: \.self) { Text(verbatim: $0).tag($0) }
                            }.labelsHidden().focused($focusedField, equals: variable.name).accessibilityLabel(variable.name)
                        } else {
                            PromptTextEditor(text: value, label: variable.name, focusOnAppear: variable.name == entry.variables.first?.name)
                                .frame(height: 60)
                        }
                    }
                }
                if !entry.variables.isEmpty {
                    Button("Reset to saved defaults") { library.values = entry.defaultValues }.font(.caption)
                }
                Divider()
                Text("Completed template").font(.headline)
                switch library.rendered {
                case .success(let text):
                    Text(verbatim: text).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                case .failure(let error): Text(error.localizedDescription).foregroundStyle(.secondary)
                case nil: EmptyView()
                }
                if !entry.images.isEmpty {
                    ForEach(entry.images) { image in
                        if let preview = NSImage(data: image.png) {
                            Image(nsImage: preview).resizable().scaledToFit().frame(maxHeight: 120)
                                .accessibilityLabel(image.label)
                        }
                        Text(verbatim: image.label).font(.caption)
                    }
                    Text("Press ⌘V in your destination. If it drops images, use Copy next and paste each part in order.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                #if COPYSTORY_PRODUCTION && !COPYSTORY_TESTFLIGHT_DIRECT_PASTE
                Text("Copy this text, then press ⌘V in your destination app. Submit it there when you’re ready.").font(.caption).foregroundStyle(.secondary)
                #else
                Text("Paste inserts this text in your previous app. Submit it there when you’re ready.").font(.caption).foregroundStyle(.secondary)
                #endif
                }
            }
        }.disabled(model.busy)
    }
}

private struct VariableEditor: View {
    @Binding var variable: TemplateVariable
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(variable.name).font(.headline)
                Spacer()
                Picker("Input for \(variable.name)", selection: Binding(get: { variable.kind }, set: { kind in
                    variable.kind = kind
                    if kind == .dropdown {
                        if variable.options.isEmpty { variable.options = variable.defaultValue.isEmpty ? ["Option 1", "Option 2"] : [variable.defaultValue] }
                        if !variable.options.contains(variable.defaultValue) { variable.defaultValue = variable.options.first ?? "" }
                    }
                })) {
                    Text("Text").tag(TemplateVariable.Kind.text)
                    Text("Dropdown").tag(TemplateVariable.Kind.dropdown)
                }.labelsHidden().frame(width: 140)
            }
            if variable.kind == .dropdown {
                Text("Options · one per line").font(.caption).foregroundStyle(.secondary)
                PromptTextEditor(text: Binding(get: { variable.options.joined(separator: "\n") }, set: { text in
                    variable.options = text.components(separatedBy: "\n")
                    if !variable.options.contains(variable.defaultValue) { variable.defaultValue = variable.options.first ?? "" }
                }), label: "Options for \(variable.name)").frame(height: 75)
                Picker("Saved default", selection: $variable.defaultValue) {
                    ForEach(Array(variable.options.enumerated()), id: \.offset) { _, option in Text(verbatim: option.isEmpty ? "Empty option" : option).tag(option) }
                }.accessibilityLabel("Default for \(variable.name)")
            } else {
                Text("Saved default · optional").font(.caption).foregroundStyle(.secondary)
                PromptTextEditor(text: $variable.defaultValue, label: "Default for \(variable.name)").frame(height: 54)
            }
        }.padding(12).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
}
