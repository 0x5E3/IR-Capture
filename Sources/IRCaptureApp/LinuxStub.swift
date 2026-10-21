#if true
// The app is macOS-only (SwiftUI + CoreAudio). This keeps `swift build` working elsewhere.
@main struct IRCaptureAppStub { static func main() { print("IR Capture is a macOS app.") } }
#endif
