import UIKit
import XCTest

/// Zaslonski posnetki iPada v obeh orientacijah. simctl naprave ne zna zasukati, iPadOS pa
/// aplikaciji z večopravilnostjo ne dovoli, da bi orientacijo vsilila sama – zato UI test.
/// Mapo za posnetke poda skripta s TEST_RUNNER_SHOTS_DIR (v testu je to SHOTS_DIR).
final class ScreenshotTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = true
    }

    func testIPadLight() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Samo za iPad.")
        shoot("ipad-1-lezece-izpostavljeno.png", ["-section", "highlights", "-selectFirst"], .landscapeLeft)
        shoot("ipad-2-lezece-kategorija.png", ["-section", "categories"], .landscapeLeft)
        shoot("ipad-3-pokoncno.png", ["-section", "highlights", "-selectFirst"], .portrait)
        shoot("ipad-5-lezece-vodic.png", ["-section", "guide"], .landscapeLeft)
    }

    /// Skripta pred tem preklopi simulator v temni način.
    func testIPadDark() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Samo za iPad.")
        shoot("ipad-4-temni-nacin.png", ["-section", "highlights", "-selectFirst"], .landscapeLeft)
    }

    private func shoot(_ file: String, _ args: [String], _ orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        let app = XCUIApplication()
        app.launchArguments = ["-demo"] + args
        app.launch()
        XCUIDevice.shared.orientation = orientation
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 60), "Aplikacija se ni odprla: \(file)")
        sleep(6)  // slike izdelkov in animacije

        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = file
        attachment.lifetime = .keepAlways
        add(attachment)

        // Ležeči posnetek ima orientacijo le v metapodatkih; ponovni izris jo zapiše v slikovne točke.
        let image = shot.image
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let png = UIGraphicsImageRenderer(size: image.size, format: format).pngData { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? NSTemporaryDirectory())
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try png.write(to: dir.appendingPathComponent(file))
        } catch {
            XCTFail("Posnetka \(file) ni bilo mogoče shraniti: \(error)")
        }
    }
}
