import Foundation

enum STTStatus: Equatable {
    case idle
    case connecting
    case recording
    case error(String?)
}
