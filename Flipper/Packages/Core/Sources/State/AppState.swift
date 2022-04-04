import Inject
import Peripheral
import Foundation
import Combine
import Logging

public class AppState {
    public static let shared: AppState = .init()
    private let logger = Logger(label: "appstate")

    @Published public var isFirstLaunch: Bool {
        didSet { UserDefaultsStorage.shared.isFirstLaunch = isFirstLaunch }
    }

    @Inject private var pairedDevice: PairedDevice
    private var disposeBag: DisposeBag = .init()

    @Published public var flipper: Flipper? {
        didSet { updateState(flipper?.state) }
    }
    @Published public var archive: Archive = .shared
    @Published public var status: DeviceStatus = .noDevice

    @Published public var importQueue: [ArchiveItem] = []

    public init() {
        isFirstLaunch = UserDefaultsStorage.shared.isFirstLaunch

        pairedDevice.flipper
            .receive(on: DispatchQueue.main)
            .assign(to: \.flipper, on: self)
            .store(in: &disposeBag)
    }

    // MARK: Status

    var connectAttemptCount = 0
    let connectAttemptCountMax = 3

    // swiftlint:disable cyclomatic_complexity
    func updateState(_ newValue: FlipperState?) {
        guard let newValue = newValue else {
            status = .noDevice
            return
        }
        guard !pairedDevice.isPairingFailed else {
            pairedDevice.forget()
            return
        }
        switch status {
        // MARK: Pairing
        case .noDevice where newValue == .connecting: status = .preParing
        case .preParing where newValue == .connected: status = .pairing
        case .preParing where newValue == .disconnected: didFailToConnect()
        case .pairing where newValue == .disconnected: didDisconnect()
        case .pairing where newValue == .connected: didConnect()
        // MARK: Default
        case .connecting where newValue == .connected: didConnect()
        case .connecting where newValue == .disconnected: didFailToConnect()
        case .connected where newValue == .disconnected: didDisconnect()
        case .synchronized where newValue == .disconnected: didDisconnect()
        case .synchronizing where newValue == .disconnected: didDisconnect()
        case .unsupportedDevice where newValue == .connected: break
        default: status = .init(newValue)
        }
    }

    func didConnect() {
        status = .connected
        connectAttemptCount = 0
        logger.info("connected")

        Task {
            try await waitForDeviceInformation()
            guard validateFirmwareVersion() else {
                return
            }
            await getStorageInfo()
            await synchronizeDateTime()
            await synchronize()
        }
    }

    func waitForDeviceInformation() async throws {
        while true {
            try await Task.sleep(nanoseconds: 100 * 1_000_000)
            if flipper?.battery != nil {
                return
            }
        }
    }

    func validateFirmwareVersion() -> Bool {
        guard let version = flipper?.information?.protobufRevision else {
            logger.error("can't validate firmware version")
            status = .disconnected
            disconnect()
            return false
        }
        guard version >= .v0_3 else {
            logger.error("unsupported firmware version")
            status = .unsupportedDevice
            disconnect()
            return false
        }
        return true
    }

    func didDisconnect() {
        guard !pairedDevice.isPairingFailed else {
            status = .failed
            logger.debug("disconnected: invalid pincode or canceled")
            return
        }
        status = .disconnected
        logger.debug("disconnected: trying to reconnect")
        connect()
    }

    func didFailToConnect() {
        status = .disconnected
        guard connectAttemptCount >= connectAttemptCountMax else {
            logger.debug("failed to connect: trying again")
            connectAttemptCount += 1
            connect()
            return
        }
        status = .pairingIssue
        logger.debug("failed to connect: pairing issue")
    }

    // MARK: Connection

    public func connect() {
        pairedDevice.connect()
    }

    public func disconnect() {
        pairedDevice.disconnect()
    }

    public func forgetDevice() {
        pairedDevice.forget()
    }

    // MARK: Synchronization

    public func synchronize() async {
        guard flipper?.state == .connected else { return }
        guard status != .unsupportedDevice else { return }
        guard status != .synchronizing else { return }
        status = .synchronizing
        await measure("syncing archive") {
            await archive.synchronize()
        }
        status = .synchronized
        Task {
            try await Task.sleep(nanoseconds: 3_000 * 1_000_000)
            guard status == .synchronized else { return }
            status = .init(flipper?.state)
        }
    }

    func synchronizeDateTime() async {
        guard status == .connected else { return }
        status = .synchronizing
        await measure("setting datetime") {
            try? await RPC.shared.setDate()
        }
        status = .init(flipper?.state)
    }

    func getStorageInfo() async {
        var storage = flipper?.storage ?? .init()
        if let intSpace = try? await RPC.shared.getStorageInfo(at: "/int") {
            storage.internal = intSpace
        }
        if let extSpace = try? await RPC.shared.getStorageInfo(at: "/ext") {
            storage.external = extSpace
        }
        flipper?.storage = storage
    }

    // MARK: Sharing

    public func onOpenURL(_ url: URL) async {
        do {
            let item = try await Sharing.importKey(from: url)
            importQueue = [item]
            logger.info("key url opened")
        } catch {
            logger.error("\(error)")
        }
    }

    public var imported: SafePublisher<ArchiveItem> {
        importedSubject.eraseToAnyPublisher()
    }
    private let importedSubject = SafeSubject<ArchiveItem>()

    public func importKey(_ item: ArchiveItem) async throws {
        try await archive.importKey(item)
        logger.info("key imported")
        importedSubject.send(item)
        await synchronize()
    }

    // MARK: Debug

    func measure(_ label: String, _ task: () async -> Void) async {
        let start = Date()
        await task()
        let time = (Date().timeIntervalSince(start) * 1000).rounded() / 1000
        logger.info("\(label): \(time)s")
    }

    // MARK: App Reset

    public func reset() {
        AppReset().reset()
    }
}