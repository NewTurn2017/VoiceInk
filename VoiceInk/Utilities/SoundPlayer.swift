import AppKit

enum SoundEffect {
    case start
    case stop
}

final class SoundPlayer {
    func play(_ effect: SoundEffect) {
        switch effect {
        case .start:
            if let sound = NSSound(named: "Pop") {
                sound.play()
            } else if let sound = NSSound(named: "Tink") {
                sound.play()
            } else {
                NSSound.beep()
            }
        case .stop:
            if let sound = NSSound(named: "Basso") {
                sound.play()
            } else if let sound = NSSound(named: "Funk") {
                sound.play()
            } else {
                NSSound.beep()
            }
        }
    }
}
