import Foundation

enum STTStatus: Equatable {
    case idle
    case recording
    case processing
    case error(String?)
}
