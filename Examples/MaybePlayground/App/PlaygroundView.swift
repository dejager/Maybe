import SwiftUI
import Maybe

/// Let the system own navigation, grouping, color, and control styling. This keeps
/// the playground familiar across iOS versions, appearances, and text sizes.
struct PlaygroundView: View {
    @State private var model = PlaygroundModel()
    @State private var showingSource = false
    @State private var showingInfo = false
    @State private var showingConnection = false
    @State private var traceExpanded = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var editingInput: Bool

    var body: some View {
        NavigationStack {
            List {
                introduction
                exampleSection
                inputSection
                programSection
                resultSection
                if !model.events.isEmpty { traceSection }
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Maybe")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("About this playground", systemImage: "info.circle") { showingInfo = true }
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Replay", systemImage: "arrow.counterclockwise") {
                        editingInput = false
                        model.replay()
                    }
                    .disabled(model.recording == nil || model.isRunning)
                    .accessibilityLabel("Replay last run")
                    .accessibilityHint("Restores recorded source and input. No model calls.")
                    .accessibilityIdentifier("replay-button")
                    Spacer()
                    Button {
                        editingInput = false
                        if model.isRunning { model.stop() } else { model.run() }
                    } label: {
                        Label(model.isRunning ? "Stop" : "Run", systemImage: model.isRunning ? "stop.fill" : "play.fill")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.canRun && !model.isRunning)
                    .accessibilityIdentifier("run-button")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editingInput = false }
                }
            }
            .sheet(isPresented: $showingSource) {
                SourceEditor(model: model)
            }
            .sheet(isPresented: $showingConnection) {
                ConnectionSettings(model: model)
            }
            .sheet(isPresented: $showingInfo) {
                AboutPlayground()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { model.stop() }
            }
        }
        .tint(.blue)
    }

    private var introduction: some View {
        Text("Explore a workflow. Follow each decision.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            .listRowSeparator(.hidden)
    }

    private var exampleSection: some View {
        Section {
            Picker(selection: Binding(get: { model.selected }, set: {
                editingInput = false
                model.select($0)
                traceExpanded = false
            })) {
                ForEach(Example.allCases) { example in
                    Label(example.title, systemImage: example.symbol).tag(example)
                }
            } label: {
                Label("Example", systemImage: "square.stack")
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("example-picker")
            Button {
                editingInput = false
                showingConnection = true
            } label: {
                LabeledContent {
                    HStack {
                        Text(model.usesJev ? "JEV" : "Demo").foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                } label: {
                    Label("Model", systemImage: "cpu")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.isRunning)
            .accessibilityIdentifier("model-settings")
        } footer: {
            Text(model.usesJev
                 ? "Live decisions from JEV. Input is sent to TypeSafe when you run. API usage may incur charges."
                 : "Demo mode uses sample responses without calling JEV. Tap Model to connect JEV with your API key.")
        }
    }

    private var inputSection: some View {
        Section("Input") {
            TextField("Enter a message", text: $model.input, axis: .vertical)
                .lineLimit(2...6)
                .padding(.vertical, 4)
                .focused($editingInput)
                .disabled(model.isRunning)
                .accessibilityLabel("Program input")
                .accessibilityIdentifier("program-input")
        }
    }

    private var programSection: some View {
        Section("Program") {
            Button {
                editingInput = false
                showingSource = true
            } label: {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        if dynamicTypeSize.isAccessibilitySize {
                            Text("Edit Source")
                                .font(.body)
                        } else {
                            Label(model.selected.filename, systemImage: "chevron.left.forwardslash.chevron.right")
                                .font(.subheadline.weight(.medium))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    // A multiline code preview adds excessive scrolling at accessibility
                    // sizes. The full, scalable editor is still one tap away.
                    if dynamicTypeSize.isAccessibilitySize {
                        Text(model.selected.filename)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(sourcePreview)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(model.selected.filename)")
            .accessibilityHint("Opens the source editor.")
            .accessibilityIdentifier("source-disclosure")
        }
    }

    private var sourcePreview: String {
        model.source.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .prefix(4).joined(separator: "\n")
    }

    private var resultSection: some View {
        Section {
            HStack(spacing: 10) {
                if model.isRunning {
                    ProgressView().accessibilityLabel("Running")
                } else {
                    Image(systemName: statusSymbol)
                        .foregroundStyle(statusColor)
                        .accessibilityHidden(true)
                }
                Text(model.status.label)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("run-status")
            }
            if case .failed(let message) = model.status {
                Text(message)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("run-error")
            }
            if model.output.isEmpty {
                Text(model.isRunning ? "Waiting for a response…" : model.status == .ready ? "Run the program to see its output." : "No output.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.output.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 2)
                        .accessibilityIdentifier("output-\(index)")
                }
            }
            if let url = model.exportURL {
                ShareLink(item: url) {
                    Label("Share Recording", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("share-recording")
            }
            if let error = model.exportError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Result")
        } footer: {
            if model.recording != nil { Text("Recordings include the program, input, responses, and decisions.") }
        }
    }

    private var traceSection: some View {
        Section {
            DisclosureGroup(isExpanded: $traceExpanded) {
                ForEach(Array(model.events.enumerated()), id: \.offset) { _, event in
                    TraceRow(event: event, isLive: model.lastRunUsedJev)
                        .padding(.vertical, 6)
                }
            } label: {
                Label {
                    HStack {
                        Text("Decisions")
                        Spacer()
                        Text(model.events.count, format: .number)
                            .foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "list.bullet") }
            }
            .accessibilityIdentifier("trace-disclosure")
        }
    }

    private var statusSymbol: String {
        switch model.status {
        case .ready: "play.circle"
        case .running: "ellipsis.circle"
        case .complete: "checkmark.circle.fill"
        case .replayed: "arrow.counterclockwise.circle.fill"
        case .cancelled: "stop.circle"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .complete: .green
        case .replayed: .blue
        case .failed: .red
        default: .secondary
        }
    }
}

/// Editing has its own native sheet so code gets the full available width and
/// the keyboard never competes with the run controls or decision trace.
private struct SourceEditor: View {
    @Bindable var model: PlaygroundModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $model.source)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 16)
                .disabled(model.isRunning)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Maybe source code")
                .accessibilityIdentifier("source-editor")
                .navigationTitle(model.selected.filename)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("source-done")
                    }
                }
        }
    }
}

private struct AboutPlayground: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Maybe Playground", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.headline)
                    Text("Try small programs that generate text and make decisions with confidence thresholds.")
                }
                Section("Models") {
                    Text("Demo simulates responses locally. Choose JEV in the Model row to connect directly with your TypeSafe API key. JEV makes decisions; text generation requires a separate writer.")
                    Text("Replay repeats a completed run using its recorded responses and random choices.")
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// A session-only connection: saving settings never sends a request.
private struct ConnectionSettings: View {
    let model: PlaygroundModel
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("TypeSafe API key", text: $key)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("jev-api-key")
                    Link("Get an API Key", destination: URL(string: "https://console.typesafe.ai/settings/keys")!)
                } header: { Text("JEV") } footer: {
                    Text("Your key stays in memory for this session. Run sends your input and decision criteria directly to TypeSafe. API usage may incur charges.")
                }
                Section {
                    Text("Inbox and Chaos work with JEV. Rewrite uses text generation, which JEV does not provide.")
                    if model.usesJev {
                        Text("JEV is configured for this session. Enter a new key to replace it.")
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
                Section {
                    Button("Use Demo and Forget Key") {
                        try? model.configureJev(apiKey: nil)
                        key = ""
                        dismiss()
                    }
                    .accessibilityIdentifier("forget-jev-key")
                }
            }
            .navigationTitle("Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use JEV") {
                        do {
                            try model.configureJev(apiKey: key)
                            key = ""
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("use-jev")
                }
            }
        }
    }
}

private struct TraceRow: View {
    let event: RunEvent
    let isLive: Bool

    private var probabilities: [(String, Double)] {
        guard case .object(let details) = event.detail,
              case .object(let values) = details["probabilities"] else { return [] }
        return values.compactMap { key, value -> (String, Double)? in
            guard case .number(let number) = value, number.isFinite else { return nil }
            return (key, number)
        }.sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 > $1.1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(event.kind == .judge ? "Judgment" : event.kind.rawValue.capitalized)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Line \(event.line)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text(event.text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(probabilities, id: \.0) { label, probability in
                VStack(spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(label).font(.subheadline)
                        Spacer()
                        Text(probability, format: .percent.precision(.fractionLength(0)))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(max(probability, 0), 1))
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(isLive ? "Model" : "Simulated") probability for \(label)")
                .accessibilityValue(probability.formatted(.percent.precision(.fractionLength(0))))
            }
            if !probabilities.isEmpty {
                Text(isLive ? "JEV probabilities · model estimates" : "Simulated scores · not calibrated probabilities")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("Light") { PlaygroundView() }
#Preview("Dark") { PlaygroundView().preferredColorScheme(.dark) }
