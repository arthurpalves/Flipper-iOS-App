import XCTest
import Core
import Injector

@testable import UI

class ConnectionsViewModelTests: XCTestCase {
    func testStateWhenBluetoothIsPoweredOff() {
        let connector = MockBluetoothConnector(initialState: .notReady(.poweredOff)) {
            XCTFail("BluetoothConnector.startScanForPeripherals is called unexpectedly")
        }

        let target = Self.createTarget(connector)
        XCTAssertEqual(target.state, .notReady(.poweredOff))
    }

    func testStateWhenBluetoothIsUnauthorized() {
        let connector = MockBluetoothConnector(initialState: .notReady(.unauthorized)) {
            XCTFail("BluetoothConnector.startScanForPeripherals is called unexpectedly")
        }

        let target = Self.createTarget(connector)
        XCTAssertEqual(target.state, .notReady(.unauthorized))
    }

    func testStateWhenBluetoothIsUnsupported() {
        let connector = MockBluetoothConnector(initialState: .notReady(.unsupported)) {
            XCTFail("BluetoothConnector.startScanForPeripherals is called unexpectedly")
        }

        let target = Self.createTarget(connector)
        XCTAssertEqual(target.state, .notReady(.unsupported))
    }

    func testStateWhileScanningDevices() {
        let startScanExpectation = self.expectation(description: "BluetoothConnector.startScanForPeripherals")
        let connector = MockBluetoothConnector(onStartScanForPeripherals: startScanExpectation.fulfill)

        let target = Self.createTarget(connector)
        XCTAssertEqual(target.state, .notReady(.preparing))
        connector.statusSubject.value = .ready
        self.waitForExpectations(timeout: 0.1)
        XCTAssertEqual(target.state, .ready)
        let peripheral = Peripheral(id: UUID(), name: "Device 42", state: .disconnected)
        connector.peripheralsSubject.value.append(peripheral)
        XCTAssertEqual(target.peripherals, [peripheral])
    }

    func testStopScanIsCalledOnDeinit() {
        let startScanExpectation = self.expectation(description: "BluetoothConnector.startScanForPeripherals")
        let stopScanExpectation = self.expectation(description: "BluetoothConnector.stopScanForPeripherals")
        let connector = MockBluetoothConnector(
            initialState: .ready,
            onStartScanForPeripherals: startScanExpectation.fulfill,
            onStopScanForPeripherals: stopScanExpectation.fulfill)

        var target: ConnectionsViewModel? = Self.createTarget(connector)
        XCTAssertEqual(target?.state, .ready)
        XCTAssertEqual(target?.peripherals, [])
        target = nil
        self.waitForExpectations(timeout: 0.1)
    }

    private static func createTarget(_ connector: BluetoothCentral & BluetoothConnector) -> ConnectionsViewModel {
        let container = Container.shared
        container.register(instance: connector, as: BluetoothCentral.self)
        container.register(instance: connector, as: BluetoothConnector.self)
        container.register(MockStorage.init, as: DeviceStorage.self)
        container.register(MockStorage.init, as: ArchiveStorage.self)
        return ConnectionsViewModel()
    }
}

private class MockBluetoothConnector: BluetoothCentral, BluetoothConnector {
    private let onStartScanForPeripherals: () -> Void
    private let onStopScanForPeripherals: (() -> Void)?
    private let onConnect: (() -> Void)?
    let peripheralsSubject = SafeSubject([Peripheral]())
    let statusSubject: SafeSubject<BluetoothStatus>
    // TODO: Move to separate protocol
    var connectedPeripheralsSubject: SafeSubject<[Peripheral]>

    var receivedSubject: SafeSubject<[UInt8]>

    init(
        initialState: BluetoothStatus = .notReady(.preparing),
        connectedPeripherals: [Peripheral] = [],
        onStartScanForPeripherals: @escaping () -> Void,
        onStopScanForPeripherals: (() -> Void)? = nil,
        onConnect: (() -> Void)? = nil
    ) {
        self.onStartScanForPeripherals = onStartScanForPeripherals
        self.onStopScanForPeripherals = onStopScanForPeripherals
        self.onConnect = onConnect
        self.statusSubject = SafeSubject(initialState)
        self.connectedPeripheralsSubject = SafeSubject(connectedPeripherals)
        self.receivedSubject = SafeSubject([])
    }

    var peripherals: SafePublisher<[Peripheral]> {
        self.peripheralsSubject.eraseToAnyPublisher()
    }

    var connectedPeripherals: SafePublisher<[Peripheral]> {
        self.connectedPeripheralsSubject.eraseToAnyPublisher()
    }

    var status: SafePublisher<BluetoothStatus> {
        self.statusSubject.eraseToAnyPublisher()
    }

    var received: SafePublisher<[UInt8]> {
        self.receivedSubject.eraseToAnyPublisher()
    }

    func startScanForPeripherals() {
        self.onStartScanForPeripherals()
    }

    func stopScanForPeripherals() {
        self.onStopScanForPeripherals?()
    }

    func connect(to uuid: UUID) {
        self.onConnect?()
    }

    func disconnect(from uuid: UUID) {
    }

    func send(_ bytes: [UInt8], to identifier: UUID) {
    }
}

private class MockStorage: DeviceStorage, ArchiveStorage {
    var pairedDevice: Peripheral? {
        get { nil }
        set { }
    }

    var items: [ArchiveItem] {
        get { [] }
        set { }
    }
}
