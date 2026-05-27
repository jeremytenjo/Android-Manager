//
//  ContentView.swift
//  Android Manager
//
//  Created by Jeremy Tenjo on 2026-05-27.
//

import SwiftUI
import Foundation
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var connectedDevices: [AndroidDevice] = []
    @State private var selectedDevice: AndroidDevice?
    @State private var destinationFolder = "Downloads"
    @State private var transferItems: [TransferItem] = []
    @State private var isShowingFilePicker = false
    @State private var isTransferring = false
    @State private var isRefreshingDevices = false
    @State private var isPollingDevices = false
    @State private var deviceMessage = "Connect your Android phone in File Transfer mode."

    private var readyItems: [TransferItem] {
        transferItems.filter { $0.status != .complete && $0.sourceURL != nil }
    }

    private var totalSize: Int64 {
        transferItems.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        HStack(spacing: 0) {
            deviceSidebar
                .frame(width: 260)

            Divider()

            transferWorkspace
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 620)
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .task {
            await startDevicePolling()
        }
    }

    private var deviceSidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Android Manager")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button {
                    Task { await refreshConnectedDevices() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshingDevices)
                .help("Refresh devices")
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)

            VStack(alignment: .leading, spacing: 8) {
                Text(isRefreshingDevices ? "Scanning" : "Connected devices")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 18)

                if connectedDevices.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "cable.connector.slash")
                            .font(.title2)
                            .foregroundStyle(.secondary)

                        Text(deviceMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 10)
                } else {
                    ForEach(connectedDevices) { device in
                        Button {
                            selectedDevice = device
                        } label: {
                            DeviceRow(device: device, isSelected: selectedDevice?.id == device.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var transferWorkspace: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    transferSummary
                    destinationPicker
                    fileQueue
                }
                .padding(28)
                .frame(maxWidth: 980, alignment: .topLeading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: "arrow.up.doc.on.clipboard")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 52, height: 52)
                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text("Transfer files")
                    .font(.title2.weight(.semibold))

                Text("Send documents, media, and folders to your Android phone.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isShowingFilePicker = true
            } label: {
                Label("Add Files", systemImage: "plus")
            }
            .buttonStyle(.bordered)

            Button {
                Task { await startTransfer() }
            } label: {
                Label(isTransferring ? "Transferring" : "Transfer", systemImage: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isTransferring || readyItems.isEmpty || selectedDevice == nil)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(.regularMaterial)
    }

    private var transferSummary: some View {
        HStack(spacing: 14) {
            SummaryTile(title: "Device", value: selectedDevice?.name ?? "No device", icon: "iphone.gen3", tint: .green)
            SummaryTile(title: "Files", value: "\(transferItems.count)", icon: "doc.on.doc", tint: .orange)
            SummaryTile(title: "Total size", value: ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file), icon: "externaldrive", tint: .purple)
        }
    }

    private var destinationPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Destination")
                .font(.headline)

            Picker("Folder", selection: $destinationFolder) {
                Text("Downloads").tag("Downloads")
                Text("Pictures").tag("Pictures")
                Text("Movies").tag("Movies")
                Text("Music").tag("Music")
                Text("Documents").tag("Documents")
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Text(destinationStatusText)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }

    private var fileQueue: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Queue")
                    .font(.headline)

                Spacer()

                Button {
                    transferItems.removeAll()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(transferItems.isEmpty || isTransferring)
            }

            if transferItems.isEmpty {
                emptyQueue
            } else {
                VStack(spacing: 0) {
                    ForEach(transferItems) { item in
                        TransferRow(item: item) {
                            transferItems.removeAll { $0.id == item.id }
                        }
                        .disabled(isTransferring)

                        if item.id != transferItems.last?.id {
                            Divider()
                        }
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary)
                )
            }
        }
    }

    private var emptyQueue: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)

            Text("No files selected")
                .font(.headline)

            Button {
                isShowingFilePicker = true
            } label: {
                Label("Choose Files", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        )
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }

        let importedItems = urls.map { url in
            TransferItem(
                name: url.lastPathComponent,
                sourceURL: url,
                size: fileSize(for: url),
                progress: 0,
                status: .queued,
                errorMessage: nil
            )
        }

        transferItems.append(contentsOf: importedItems)
    }

    private func fileSize(for url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        return Int64(values?.fileSize ?? values?.totalFileAllocatedSize ?? 0)
    }

    private func refreshConnectedDevices() async {
        isRefreshingDevices = true
        defer { isRefreshingDevices = false }

        await updateConnectedDevices()
    }

    private func startDevicePolling() async {
        guard !isPollingDevices else { return }

        isPollingDevices = true
        defer { isPollingDevices = false }

        await updateConnectedDevices()

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(4))

            guard !isTransferring else {
                continue
            }

            await updateConnectedDevices()
        }
    }

    private func updateConnectedDevices() async {
        do {
            let devices = try await LibMTPTransferService.detectDevices()
            let selectedDeviceID = selectedDevice?.id

            connectedDevices = devices
            selectedDevice = devices.first { $0.id == selectedDeviceID } ?? devices.first
            deviceMessage = devices.isEmpty ? "No MTP devices found. Unlock your phone and set USB mode to File Transfer." : ""
        } catch {
            connectedDevices = []
            selectedDevice = nil
            deviceMessage = error.localizedDescription
        }
    }

    private var destinationStatusText: String {
        "Ready to send with libmtp to \(destinationFolder)."
    }

    private func startTransfer() async {
        isTransferring = true
        defer { isTransferring = false }

        let itemIDs = transferItems.map(\.id)

        for itemID in itemIDs {
            guard let itemIndex = transferItems.firstIndex(where: { $0.id == itemID }) else {
                continue
            }

            guard transferItems[itemIndex].status != .complete else {
                continue
            }

            guard let sourceURL = transferItems[itemIndex].sourceURL else {
                transferItems[itemIndex].status = .failed
                transferItems[itemIndex].errorMessage = "Choose the file again before transferring."
                continue
            }

            transferItems[itemIndex].status = .transferring
            transferItems[itemIndex].errorMessage = nil
            transferItems[itemIndex].progress = 0.15

            do {
                try await LibMTPTransferService.send(fileAt: sourceURL, toFolderNamed: destinationFolder)
                transferItems[itemIndex].progress = 1
                transferItems[itemIndex].status = .complete
            } catch {
                transferItems[itemIndex].progress = 0
                transferItems[itemIndex].status = .failed
                transferItems[itemIndex].errorMessage = error.localizedDescription
            }
        }
    }
}

private struct AndroidDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let model: String
    let batteryLevel: Int?
    let isConnected: Bool

    static let sampleDevices = [
        AndroidDevice(id: "preview-device", name: "Galaxy A54 5G", model: "MTP connected", batteryLevel: nil, isConnected: true)
    ]
}

private struct TransferItem: Identifiable {
    let id = UUID()
    let name: String
    let sourceURL: URL?
    let size: Int64
    var progress: Double
    var status: TransferStatus
    var errorMessage: String?

    static let sampleItems: [TransferItem] = []
}

private enum TransferStatus: String {
    case queued = "Queued"
    case transferring = "Transferring"
    case complete = "Complete"
    case failed = "Failed"

    var color: Color {
        switch self {
        case .queued:
            return .secondary
        case .transferring:
            return .blue
        case .complete:
            return .green
        case .failed:
            return .red
        }
    }
}

private enum LibMTPTransferError: LocalizedError {
    case toolMissing
    case detectFailed(String)
    case sendFailed(String)

    var errorDescription: String? {
        switch self {
        case .toolMissing:
            return "libmtp tools were not found. Install them with: brew install libmtp"
        case .detectFailed(let message):
            return message
        case .sendFailed(let message):
            return message
        }
    }
}

private struct LibMTPTransferService {
    static func detectDevices() async throws -> [AndroidDevice] {
        try await Task.detached {
            guard let command = mtpDetectCommand() else {
                throw LibMTPTransferError.toolMissing
            }

            let output = try run(command: command, arguments: [], startupErrorMessage: "Could not start mtp-detect.")

            if output.lowercased().contains("no raw devices found") || output.lowercased().contains("no mtp devices") {
                return []
            }

            if let device = parseDevice(from: output) {
                return [device]
            }

            if output.lowercased().contains("unable to open raw device") {
                throw LibMTPTransferError.detectFailed("The phone is busy. Quit MacDroid or any other app using MTP, then refresh.")
            }

            return []
        }.value
    }

    static func send(fileAt sourceURL: URL, toFolderNamed folderName: String) async throws {
        try await Task.detached {
            guard let command = mtpSendFileCommand() else {
                throw LibMTPTransferError.toolMissing
            }

            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            let remotePath = "\(folderName)/\(sourceURL.lastPathComponent)"
            let output = try run(
                command: command,
                arguments: [sourceURL.path, remotePath],
                startupErrorMessage: "Could not start mtp-sendfile."
            )

            let normalizedOutput = output.lowercased()
            let parentFolderMissing = normalizedOutput.contains("parent folder could not be found")
            let deviceMissing = normalizedOutput.contains("no mtp devices") || normalizedOutput.contains("unable to open raw device")

            guard !parentFolderMissing && !deviceMissing else {
                throw LibMTPTransferError.sendFailed(readableErrorMessage(from: output))
            }
        }.value
    }

    private nonisolated static var libMTPSearchPath: String {
        [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ].joined(separator: ":")
    }

    private nonisolated static func mtpSendFileCommand() -> (executableURL: URL, argumentsPrefix: [String])? {
        let knownPaths = [
            "/opt/homebrew/bin/mtp-sendfile",
            "/usr/local/bin/mtp-sendfile"
        ]

        if let toolPath = knownPaths.first(where: FileManager.default.fileExists(atPath:)) {
            return (URL(fileURLWithPath: toolPath), [])
        }

        return nil
    }

    private nonisolated static func mtpDetectCommand() -> (executableURL: URL, argumentsPrefix: [String])? {
        let knownPaths = [
            "/opt/homebrew/bin/mtp-detect",
            "/usr/local/bin/mtp-detect"
        ]

        if let toolPath = knownPaths.first(where: FileManager.default.fileExists(atPath:)) {
            return (URL(fileURLWithPath: toolPath), [])
        }

        return nil
    }

    private nonisolated static func run(command: (executableURL: URL, argumentsPrefix: [String]), arguments: [String], startupErrorMessage: String) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = libMTPSearchPath

        process.executableURL = command.executableURL
        process.arguments = command.argumentsPrefix + arguments
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            let executablePath = process.executableURL?.path ?? "unknown executable"
            throw LibMTPTransferError.detectFailed("\(startupErrorMessage) \(executablePath): \(error.localizedDescription)")
        }

        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw LibMTPTransferError.detectFailed(output.isEmpty ? startupErrorMessage : output)
        }

        return output
    }

    private nonisolated static func parseDevice(from output: String) -> AndroidDevice? {
        let model = value(after: "Model:", in: output)
        let manufacturer = value(after: "Manufacturer:", in: output)
        let serial = value(after: "Serial number:", in: output)

        let fallbackName = output
            .components(separatedBy: .newlines)
            .first { $0.contains("Device ") && $0.contains(" is ") }?
            .components(separatedBy: " is ")
            .last?
            .replacingOccurrences(of: "(MTP).", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let nameParts = [manufacturer, model].compactMap { value -> String? in
            guard let value, !value.isEmpty, value.lowercased() != "unknown" else { return nil }
            return value
        }

        let name = nameParts.isEmpty ? fallbackName : nameParts.joined(separator: " ")
        guard let deviceName = name, !deviceName.isEmpty else {
            return nil
        }

        return AndroidDevice(
            id: serial ?? deviceName,
            name: deviceName,
            model: "MTP connected",
            batteryLevel: nil,
            isConnected: true
        )
    }

    private nonisolated static func value(after label: String, in output: String) -> String? {
        output
            .components(separatedBy: .newlines)
            .first { $0.trimmingCharacters(in: .whitespaces).hasPrefix(label) }?
            .replacingOccurrences(of: label, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func readableErrorMessage(from output: String) -> String {
        if output.isEmpty {
            return "MTP transfer failed. Unlock the phone, set USB mode to File Transfer, and make sure no other app is using the phone."
        }

        if output.lowercased().contains("parent folder could not be found") {
            return "The selected folder was not found on the phone. Try Downloads, Pictures, Movies, Music, or Documents."
        }

        return output
    }
}

private struct DeviceRow: View {
    let device: AndroidDevice
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone.gen3")
                .font(.title3)
                .foregroundStyle(device.isConnected ? .green : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.body.weight(.medium))

                Text(device.model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(device.batteryLevel.map { "\($0)%" } ?? "MTP")
                .font(.caption.weight(.medium))
                .foregroundStyle(device.isConnected ? .green : .secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 10)
    }
}

private struct SummaryTile: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.headline)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 74)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary)
        )
    }
}

private struct TransferRow: View {
    let item: TransferItem
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 36, height: 36)
                .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(item.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    Spacer()

                    Text(item.status.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.status.color)
                }

                HStack(spacing: 10) {
                    ProgressView(value: item.progress)
                        .tint(item.status.color)

                    Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 84, alignment: .trailing)
                }

                if let errorMessage = item.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Button(action: remove) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Remove from queue")
        }
        .padding(14)
    }

    private var iconName: String {
        let lowercasedName = item.name.lowercased()

        if lowercasedName.hasSuffix(".jpg") || lowercasedName.hasSuffix(".png") || lowercasedName.hasSuffix(".heic") {
            return "photo"
        }

        if lowercasedName.hasSuffix(".mp4") || lowercasedName.hasSuffix(".mov") {
            return "film"
        }

        if lowercasedName.hasSuffix(".mp3") || lowercasedName.hasSuffix(".m4a") {
            return "music.note"
        }

        if lowercasedName.hasSuffix(".zip") {
            return "archivebox"
        }

        return "doc"
    }
}

#Preview {
    ContentView()
}
