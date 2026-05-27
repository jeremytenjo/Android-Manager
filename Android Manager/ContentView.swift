//
//  ContentView.swift
//  Android Manager
//
//  Created by Jeremy Tenjo on 2026-05-27.
//

import SwiftUI
import Foundation
import UniformTypeIdentifiers

#if canImport(GRDB)
import GRDB
#endif

struct ContentView: View {
    @State private var connectedDevices: [AndroidDevice] = []
    @State private var selectedDevice: AndroidDevice?
    @State private var deviceDatabase = DeviceDatabase.load()
    @State private var destinationFolder = "Downloads"
    @State private var transferItems: [TransferItem] = []
    @State private var isShowingFilePicker = false
    @State private var isTransferring = false
    @State private var isRefreshingDevices = false
    @State private var isPollingDevices = false
    @State private var isDropTargeted = false
    @State private var isShowingRenameDevice = false
    @State private var renamingDeviceID: String?
    @State private var deviceNameDraft = ""
    @State private var deviceMessage = "Connect your Android phone in File Transfer mode."

    private var totalSize: Int64 {
        transferItems.reduce(0) { $0 + $1.size }
    }

    private var displayedDevices: [AndroidDevice] {
        orderedDevices(from: connectedDevices)
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
        .alert("Rename Device", isPresented: $isShowingRenameDevice) {
            TextField("Device name", text: $deviceNameDraft)

            Button("Save") {
                saveRenamedDevice()
            }

            Button("Cancel", role: .cancel) {
                renamingDeviceID = nil
            }
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
                    ForEach(displayedDevices) { device in
                        HStack(spacing: 4) {
                            Button {
                                selectDevice(device)
                            } label: {
                                DeviceRow(device: device, isSelected: selectedDevice?.id == device.id)
                            }
                            .buttonStyle(.plain)

                            VStack(spacing: 4) {
                                Button {
                                    moveDevice(device, direction: .up)
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .disabled(device.id == displayedDevices.first?.id)
                                .help("Move up")

                                Button {
                                    moveDevice(device, direction: .down)
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .disabled(device.id == displayedDevices.last?.id)
                                .help("Move down")
                            }
                            .buttonStyle(.borderless)

                            Button {
                                beginRenaming(device)
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .help("Rename device")
                        }
                    }
                }
            }

            Spacer()
        }
        .background(.ultraThinMaterial)
    }

    private var transferWorkspace: some View {
        VStack(spacing: 0) {
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
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
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
                Text("History")
                    .font(.headline)

                Spacer()

                Button {
                    isShowingFilePicker = true
                } label: {
                    Label("Add Files", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .disabled(isTransferring)

                Button {
                    transferItems.removeAll()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(transferItems.isEmpty || isTransferring)
            }

            Group {
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
                    .liquidGlassPanel(cornerRadius: 12)
                }
            }
            .overlay(dropHighlight)
            .dropDestination(for: URL.self) { urls, _ in
                addTransferItems(from: urls)
                return true
            } isTargeted: { isTargeted in
                isDropTargeted = isTargeted
            }
        }
    }

    private var emptyQueue: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)

            Text("No transfer history")
                .font(.headline)

            Text("Drop or choose files to transfer immediately.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                isShowingFilePicker = true
            } label: {
                Label("Choose Files", systemImage: "folder")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .liquidGlassPanel(cornerRadius: 12)
    }

    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .allowsHitTesting(false)
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }

        addTransferItems(from: urls)
    }

    private func addTransferItems(from urls: [URL]) {
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

        Task {
            await startTransfer()
        }
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
            let selectedDeviceID = selectedDevice?.id ?? deviceDatabase.selectedDeviceID
            let didChangeDatabase = deviceDatabase.register(devices)
            let orderedDevices = orderedDevices(from: devices)
            let resolvedSelectedDevice = orderedDevices.first { $0.id == selectedDeviceID } ?? orderedDevices.first
            let didChangeSelection = deviceDatabase.selectedDeviceID != resolvedSelectedDevice?.id

            connectedDevices = devices
            selectedDevice = resolvedSelectedDevice
            deviceMessage = devices.isEmpty ? "No MTP devices found. Unlock your phone and set USB mode to File Transfer." : ""

            if let selectedDevice {
                deviceDatabase.selectedDeviceID = selectedDevice.id
            }

            if didChangeDatabase || didChangeSelection {
                deviceDatabase.save()
            }
        } catch {
            connectedDevices = []
            selectedDevice = nil
            deviceMessage = error.localizedDescription
        }
    }

    private var destinationStatusText: String {
        "Ready to send with libmtp to \(destinationFolder)."
    }

    private func orderedDevices(from devices: [AndroidDevice]) -> [AndroidDevice] {
        devices
            .enumerated()
            .map { index, device in
                (index: index, device: device.renamed(to: deviceDatabase.customName(for: device.id)))
            }
            .sorted { lhs, rhs in
                let lhsSortIndex = deviceDatabase.sortIndex(for: lhs.device.id) ?? (10_000 + lhs.index)
                let rhsSortIndex = deviceDatabase.sortIndex(for: rhs.device.id) ?? (10_000 + rhs.index)

                return lhsSortIndex == rhsSortIndex ? lhs.index < rhs.index : lhsSortIndex < rhsSortIndex
            }
            .map(\.device)
    }

    private func selectDevice(_ device: AndroidDevice) {
        selectedDevice = device
        deviceDatabase.selectedDeviceID = device.id
        deviceDatabase.save()
    }

    private func beginRenaming(_ device: AndroidDevice) {
        renamingDeviceID = device.id
        deviceNameDraft = device.name
        isShowingRenameDevice = true
    }

    private func saveRenamedDevice() {
        guard let renamingDeviceID else { return }

        deviceDatabase.renameDevice(id: renamingDeviceID, to: deviceNameDraft)
        deviceDatabase.save()
        selectedDevice = displayedDevices.first { $0.id == selectedDevice?.id }
        self.renamingDeviceID = nil
    }

    private func moveDevice(_ device: AndroidDevice, direction: MoveDirection) {
        let ids = displayedDevices.map(\.id)
        deviceDatabase.moveDevice(id: device.id, direction: direction, orderedDeviceIDs: ids)
        deviceDatabase.save()
        selectedDevice = displayedDevices.first { $0.id == selectedDevice?.id }
    }

    private func startTransfer() async {
        guard !isTransferring else { return }

        isTransferring = true
        defer { isTransferring = false }

        while let itemIndex = transferItems.firstIndex(where: { $0.status == .queued }) {
            guard selectedDevice != nil else {
                for queuedIndex in transferItems.indices where transferItems[queuedIndex].status == .queued {
                    transferItems[queuedIndex].status = .failed
                    transferItems[queuedIndex].errorMessage = "Connect an MTP device before transferring."
                }
                break
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

    func renamed(to customName: String?) -> AndroidDevice {
        guard let customName, !customName.isEmpty else {
            return self
        }

        return AndroidDevice(
            id: id,
            name: customName,
            model: model,
            batteryLevel: batteryLevel,
            isConnected: isConnected
        )
    }
}

private enum MoveDirection {
    case up
    case down
}

#if canImport(GRDB)
private struct DeviceDatabase {
    var selectedDeviceID: String?
    var devices: [DeviceRecord]
    private let databaseQueue: DatabaseQueue?

    static func load() -> DeviceDatabase {
        do {
            try FileManager.default.createDirectory(at: databaseDirectoryURL, withIntermediateDirectories: true)

            let databaseQueue = try DatabaseQueue(path: databaseURL.path)
            try migrator.migrate(databaseQueue)

            let devices = try databaseQueue.read { db in
                try Row.fetchAll(db, sql: "SELECT id, customName, sortIndex FROM devices ORDER BY sortIndex")
                    .map { row in
                        DeviceRecord(
                            id: row["id"],
                            customName: row["customName"],
                            sortIndex: row["sortIndex"]
                        )
                    }
            }

            let selectedDeviceID = try databaseQueue.read { db in
                try String.fetchOne(db, sql: "SELECT value FROM appSettings WHERE key = ?", arguments: ["selectedDeviceID"])
            }

            return DeviceDatabase(selectedDeviceID: selectedDeviceID, devices: devices, databaseQueue: databaseQueue)
        } catch {
            assertionFailure("Failed to load GRDB device database: \(error.localizedDescription)")
            return DeviceDatabase(selectedDeviceID: nil, devices: [], databaseQueue: nil)
        }
    }

    mutating func register(_ detectedDevices: [AndroidDevice]) -> Bool {
        var didChange = false
        var nextSortIndex = (devices.map(\.sortIndex).max() ?? -1) + 1

        for device in detectedDevices where recordIndex(for: device.id) == nil {
            devices.append(DeviceRecord(id: device.id, customName: nil, sortIndex: nextSortIndex))
            nextSortIndex += 1
            didChange = true
        }

        return didChange
    }

    func customName(for deviceID: String) -> String? {
        devices.first { $0.id == deviceID }?.customName
    }

    func sortIndex(for deviceID: String) -> Int? {
        devices.first { $0.id == deviceID }?.sortIndex
    }

    mutating func renameDevice(id: String, to name: String) {
        ensureRecordExists(for: id)

        guard let index = recordIndex(for: id) else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        devices[index].customName = trimmedName.isEmpty ? nil : trimmedName
    }

    mutating func moveDevice(id: String, direction: MoveDirection, orderedDeviceIDs: [String]) {
        guard let currentIndex = orderedDeviceIDs.firstIndex(of: id) else { return }

        let destinationIndex: Int
        switch direction {
        case .up:
            destinationIndex = max(orderedDeviceIDs.startIndex, currentIndex - 1)
        case .down:
            destinationIndex = min(orderedDeviceIDs.index(before: orderedDeviceIDs.endIndex), currentIndex + 1)
        }

        guard currentIndex != destinationIndex else { return }

        var reorderedIDs = orderedDeviceIDs
        let movedID = reorderedIDs.remove(at: currentIndex)
        reorderedIDs.insert(movedID, at: destinationIndex)

        for (sortIndex, deviceID) in reorderedIDs.enumerated() {
            ensureRecordExists(for: deviceID)

            if let recordIndex = recordIndex(for: deviceID) {
                devices[recordIndex].sortIndex = sortIndex
            }
        }
    }

    func save() {
        guard let databaseQueue else { return }

        do {
            try databaseQueue.write { db in
                for device in devices {
                    try db.execute(
                        sql: """
                        INSERT INTO devices (id, customName, sortIndex)
                        VALUES (?, ?, ?)
                        ON CONFLICT(id) DO UPDATE SET
                            customName = excluded.customName,
                            sortIndex = excluded.sortIndex
                        """,
                        arguments: [device.id, device.customName, device.sortIndex]
                    )
                }

                if let selectedDeviceID {
                    try db.execute(
                        sql: """
                        INSERT INTO appSettings (key, value)
                        VALUES (?, ?)
                        ON CONFLICT(key) DO UPDATE SET value = excluded.value
                        """,
                        arguments: ["selectedDeviceID", selectedDeviceID]
                    )
                } else {
                    try db.execute(sql: "DELETE FROM appSettings WHERE key = ?", arguments: ["selectedDeviceID"])
                }
            }
        } catch {
            assertionFailure("Failed to save GRDB device database: \(error.localizedDescription)")
        }
    }

    private mutating func ensureRecordExists(for id: String) {
        guard recordIndex(for: id) == nil else { return }

        let nextSortIndex = (devices.map(\.sortIndex).max() ?? -1) + 1
        devices.append(DeviceRecord(id: id, customName: nil, sortIndex: nextSortIndex))
    }

    private func recordIndex(for id: String) -> Int? {
        devices.firstIndex { $0.id == id }
    }

    private static var databaseDirectoryURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)

        return baseURL.appendingPathComponent("Android Manager", isDirectory: true)
    }

    private static var databaseURL: URL {
        databaseDirectoryURL.appendingPathComponent("device-database.sqlite")
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createDeviceStorage") { db in
            try db.create(table: "devices", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("customName", .text)
                table.column("sortIndex", .integer).notNull()
            }

            try db.create(table: "appSettings", ifNotExists: true) { table in
                table.column("key", .text).primaryKey()
                table.column("value", .text)
            }
        }

        return migrator
    }
}
#else
private struct DeviceDatabase: Codable {
    var selectedDeviceID: String?
    var devices: [DeviceRecord]

    static func load() -> DeviceDatabase {
        do {
            let data = try Data(contentsOf: databaseURL)
            return try JSONDecoder().decode(DeviceDatabase.self, from: data)
        } catch {
            return DeviceDatabase(selectedDeviceID: nil, devices: [])
        }
    }

    mutating func register(_ detectedDevices: [AndroidDevice]) -> Bool {
        var didChange = false
        var nextSortIndex = (devices.map(\.sortIndex).max() ?? -1) + 1

        for device in detectedDevices where recordIndex(for: device.id) == nil {
            devices.append(DeviceRecord(id: device.id, customName: nil, sortIndex: nextSortIndex))
            nextSortIndex += 1
            didChange = true
        }

        return didChange
    }

    func customName(for deviceID: String) -> String? {
        devices.first { $0.id == deviceID }?.customName
    }

    func sortIndex(for deviceID: String) -> Int? {
        devices.first { $0.id == deviceID }?.sortIndex
    }

    mutating func renameDevice(id: String, to name: String) {
        ensureRecordExists(for: id)

        guard let index = recordIndex(for: id) else { return }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        devices[index].customName = trimmedName.isEmpty ? nil : trimmedName
    }

    mutating func moveDevice(id: String, direction: MoveDirection, orderedDeviceIDs: [String]) {
        guard let currentIndex = orderedDeviceIDs.firstIndex(of: id) else { return }

        let destinationIndex: Int
        switch direction {
        case .up:
            destinationIndex = max(orderedDeviceIDs.startIndex, currentIndex - 1)
        case .down:
            destinationIndex = min(orderedDeviceIDs.index(before: orderedDeviceIDs.endIndex), currentIndex + 1)
        }

        guard currentIndex != destinationIndex else { return }

        var reorderedIDs = orderedDeviceIDs
        let movedID = reorderedIDs.remove(at: currentIndex)
        reorderedIDs.insert(movedID, at: destinationIndex)

        for (sortIndex, deviceID) in reorderedIDs.enumerated() {
            ensureRecordExists(for: deviceID)

            if let recordIndex = recordIndex(for: deviceID) {
                devices[recordIndex].sortIndex = sortIndex
            }
        }
    }

    func save() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try FileManager.default.createDirectory(at: Self.databaseDirectoryURL, withIntermediateDirectories: true)
            try data.write(to: Self.databaseURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to save device database: \(error.localizedDescription)")
        }
    }

    private mutating func ensureRecordExists(for id: String) {
        guard recordIndex(for: id) == nil else { return }

        let nextSortIndex = (devices.map(\.sortIndex).max() ?? -1) + 1
        devices.append(DeviceRecord(id: id, customName: nil, sortIndex: nextSortIndex))
    }

    private func recordIndex(for id: String) -> Int? {
        devices.firstIndex { $0.id == id }
    }

    private static var databaseDirectoryURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)

        return baseURL.appendingPathComponent("Android Manager", isDirectory: true)
    }

    private static var databaseURL: URL {
        databaseDirectoryURL.appendingPathComponent("device-database.json")
    }
}
#endif

private struct DeviceRecord: Codable {
    let id: String
    var customName: String?
    var sortIndex: Int
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
        .liquidGlassPanel(
            cornerRadius: 12,
            fallbackFill: isSelected ? Color.accentColor.opacity(0.14) : Color.clear
        )
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
        .liquidGlassPanel(cornerRadius: 12)
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

private extension View {
    @ViewBuilder
    func liquidGlassPanel(cornerRadius: CGFloat, fallbackFill: Color = Color(nsColor: .controlBackgroundColor)) -> some View {
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            self
                .background(fallbackFill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.quaternary)
                )
        }
    }
}

#Preview {
    ContentView()
}
