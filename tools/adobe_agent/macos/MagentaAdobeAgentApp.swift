import SwiftUI
import AppKit

@main
struct MagentaAdobeAgentApp: App {
    var body: some Scene {
        WindowGroup {
            SetupView()
                .frame(minWidth: 700, minHeight: 620)
        }
        .windowResizability(.contentSize)
    }
}

struct SetupView: View {
    @State private var serverURL = "http://192.168.1.75:5010"
    @State private var pairingCode = ""
    @State private var machineName = Host.current().localizedName ?? "Mac prestampa"
    @State private var photoshopApp = "Adobe Photoshop 2024"
    @State private var illustratorApp = "Adobe Illustrator"
    @State private var rootFolder = "/Users/Shared/MagentaAdobe"
    @State private var busy = false
    @State private var connected = false
    @State private var statusText = "Inserisci il codice creato dal gestionale."
    @State private var statusIsError = false

    private var installedPhotoshop: [String] {
        applicationNames(prefix: "Adobe Photoshop")
    }

    private var installedIllustrator: [String] {
        applicationNames(prefix: "Adobe Illustrator")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 36))
                    .foregroundStyle(.pink)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Magenta Adobe Agent")
                        .font(.title.bold())
                    Text("Configurazione guidata del Mac di prestampa")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("1. Collegamento al gestionale") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Indirizzo gestionale") {
                        TextField("http://192.168.1.55:5000", text: $serverURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 360)
                    }
                    LabeledContent("Codice temporaneo") {
                        TextField("000-000", text: $pairingCode)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 160)
                    }
                    LabeledContent("Nome del Mac") {
                        TextField("Mac prestampa 1", text: $machineName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 360)
                    }
                }
                .padding(8)
            }

            GroupBox("2. Applicazioni Adobe") {
                VStack(alignment: .leading, spacing: 12) {
                    applicationPicker(
                        label: "Photoshop",
                        selection: $photoshopApp,
                        applications: installedPhotoshop,
                        expected: "Adobe Photoshop 2024"
                    )
                    applicationPicker(
                        label: "Illustrator",
                        selection: $illustratorApp,
                        applications: installedIllustrator,
                        expected: "Adobe Illustrator"
                    )
                }
                .padding(8)
            }

            GroupBox("3. Risorse condivise") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Cartella principale") {
                        TextField("/Users/Shared/MagentaAdobe", text: $rootFolder)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 360)
                    }
                    Text("Verranno create automaticamente le cartelle per azioni, script, maschere e log.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
            }

            HStack {
                Image(systemName: statusIsError ? "exclamationmark.triangle.fill" : (connected ? "checkmark.circle.fill" : "info.circle"))
                    .foregroundStyle(statusIsError ? .red : (connected ? .green : .secondary))
                Text(statusText)
                    .foregroundStyle(statusIsError ? .red : .primary)
                Spacer()
                if busy {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(connected ? "Riconfigura e avvia" : "Collega e avvia") {
                    connectAndStart()
                }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
                .disabled(busy || pairingCode.filter(\.isNumber).count != 6)
            }
        }
        .padding(28)
        .onAppear {
            if let detected = installedPhotoshop.first(where: { $0.contains("2024") }) {
                photoshopApp = detected
            }
            if let detected = installedIllustrator.first {
                illustratorApp = detected
            }
        }
    }

    @ViewBuilder
    private func applicationPicker(
        label: String,
        selection: Binding<String>,
        applications: [String],
        expected: String
    ) -> some View {
        LabeledContent(label) {
            if applications.isEmpty {
                HStack {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    TextField(expected, text: selection)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 330)
                }
            } else {
                Picker(label, selection: selection) {
                    ForEach(applications, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .frame(width: 360)
            }
        }
    }

    private func applicationNames(prefix: String) -> [String] {
        let applicationsURL = URL(fileURLWithPath: "/Applications")
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: applicationsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension == "app" && $0.deletingPathExtension().lastPathComponent.hasPrefix(prefix) }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    private func connectAndStart() {
        busy = true
        statusIsError = false
        statusText = "Associazione e configurazione in corso…"

        let values = (
            serverURL.trimmingCharacters(in: .whitespacesAndNewlines),
            pairingCode,
            machineName.trimmingCharacters(in: .whitespacesAndNewlines),
            photoshopApp,
            illustratorApp,
            rootFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard values.0.hasPrefix("http://") || values.0.hasPrefix("https://") else {
                    throw SetupError.message("L’indirizzo del gestionale deve iniziare con http:// o https://")
                }
                let helper = try helperURL()
                let templates = URL(fileURLWithPath: values.5)
                    .appendingPathComponent("illustrator/templates").path
                let scripts = URL(fileURLWithPath: values.5)
                    .appendingPathComponent("illustrator/scripts").path
                let result = try run(
                    executable: "/usr/bin/python3",
                    arguments: [
                        helper.path,
                        "--server", values.0,
                        "--name", values.2,
                        "--photoshop-app", values.3,
                        "--illustrator-app", values.4,
                        "--template-root", templates,
                        "--script-root", scripts,
                        "--pair", values.1
                    ]
                )
                try installLaunchAgent(helper: helper)
                DispatchQueue.main.async {
                    connected = true
                    busy = false
                    statusIsError = false
                    statusText = result.isEmpty ? "Mac collegato e agente avviato." : result
                }
            } catch {
                DispatchQueue.main.async {
                    busy = false
                    statusIsError = true
                    statusText = error.localizedDescription
                }
            }
        }
    }

    private func helperURL() throws -> URL {
        guard let helper = Bundle.main.url(forResource: "adobe_agent", withExtension: "py") else {
            throw SetupError.message("Componente agente non trovato nell’applicazione.")
        }
        return helper
    }

    private func installLaunchAgent(helper: URL) throws {
        let fileManager = FileManager.default
        let library = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let support = library.appendingPathComponent("Application Support/Magenta Adobe Agent")
        let logs = support.appendingPathComponent("logs")
        let launchAgents = library.appendingPathComponent("LaunchAgents")
        try fileManager.createDirectory(at: logs, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: launchAgents, withIntermediateDirectories: true)

        let label = "it.magenta.adobe-agent"
        let plistURL = launchAgents.appendingPathComponent("\(label).plist")
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/python3", helper.path, "--poll-seconds", "2"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": logs.appendingPathComponent("agent.log").path,
            "StandardErrorPath": logs.appendingPathComponent("agent-error.log").path
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL, options: .atomic)

        let domain = "gui/\(getuid())"
        _ = try? run(executable: "/bin/launchctl", arguments: ["bootout", domain, plistURL.path])
        _ = try run(executable: "/bin/launchctl", arguments: ["bootstrap", domain, plistURL.path])
    }

    private func run(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw SetupError.message(error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? output : error)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SetupError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let value): return value
        }
    }
}
