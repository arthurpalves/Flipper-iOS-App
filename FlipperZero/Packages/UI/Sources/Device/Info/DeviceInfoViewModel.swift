import Core
import Combine
import Inject
import struct Foundation.UUID

@MainActor
class DeviceInfoViewModel: ObservableObject {
    @Inject var connector: BluetoothConnector
    @Inject var pairedDevice: PairedDevice
    var disposeBag = DisposeBag()

    @Published var device: Peripheral?

    var name: String {
        device?.name ?? .noDevice
    }

    var uuid: String {
        device?.id.uuidString ?? .noDevice
    }

    init() {
        pairedDevice.peripheral
            .sink { [weak self] device in
                self?.device = device
            }
            .store(in: &disposeBag)
    }

    func disconnectFlipper() {
        pairedDevice.disconnect()
    }
}
