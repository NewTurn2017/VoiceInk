import Foundation

protocol STTEngine: AnyObject {
    var onTranscript: ((String) -> Void)? { get set }
    var onStatusChange: ((STTStatus) -> Void)? { get set }
    var onAudioLevel: ((Float) -> Void)? { get set }
    var currentStatus: STTStatus { get }

    func start()
    func stop()
}
