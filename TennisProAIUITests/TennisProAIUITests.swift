import XCTest

final class TennisProAIUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - 1. Initial Onboarding UI Test (Simulator & Device)

    @MainActor
    func testInitialOnboardingFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()

        let nameField = app.textFields["onboarding.nameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Taylor Morgan")

        let completeButton = app.buttons["onboarding.completeButton"]
        XCTAssertTrue(completeButton.exists)
        completeButton.tap()

        let quickRecordButton = app.buttons["dashboard.quickStartRecordingButton"]
        XCTAssertTrue(quickRecordButton.waitForExistence(timeout: 5))
    }

    // MARK: - 2. Start & Stop Recording + Save Video + Create Clip (Simulator via Mock MP4 Writer & Device)

    @MainActor
    func testStartAndStopRecordingAndCreateVideoClip() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-skip-onboarding"]
        app.launch()

        // Navigate to Record tab via Dashboard CTA
        app.buttons["dashboard.quickStartRecordingButton"].tap()

        let startButton = app.buttons["recording.startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.tap()

        let stopButton = app.buttons["recording.stopButton"]
        XCTAssertTrue(stopButton.waitForExistence(timeout: 5))
        sleep(2)
        stopButton.tap()

        // Save recording sheet appears
        let saveConfirmButton = app.buttons["recording.confirmSaveButton"]
        XCTAssertTrue(saveConfirmButton.waitForExistence(timeout: 8))
        saveConfirmButton.tap()

        // Navigate to Videos tab and open the newly saved recording
        app.tabBars.buttons["Videos"].tap()
        let firstVideoPredicate = NSPredicate(format: "identifier BEGINSWITH 'library.videoRow.'")
        let firstVideoRow = app.buttons.matching(firstVideoPredicate).firstMatch
        XCTAssertTrue(firstVideoRow.waitForExistence(timeout: 5))
        firstVideoRow.tap()

        // Open Highlight Cutter and export a clip
        let openEditorButton = app.buttons["videoDetail.openEditorButton"]
        XCTAssertTrue(openEditorButton.waitForExistence(timeout: 5))
        openEditorButton.tap()

        let exportClipButton = app.buttons["editor.exportClipButton"]
        XCTAssertTrue(exportClipButton.waitForExistence(timeout: 5))
        exportClipButton.tap()
    }

    // MARK: - 3. Enter Live Match Scores & Save Match (Simulator & Device)

    @MainActor
    func testEnterMatchScoresAndUndo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-skip-onboarding"]
        app.launch()

        app.buttons["dashboard.scorecardQuickButton"].tap()

        let newLiveButton = app.buttons["scorecardList.newLiveButton"]
        XCTAssertTrue(newLiveButton.waitForExistence(timeout: 5))
        newLiveButton.tap()

        let oppField = app.textFields["newMatch.opponentNameField"]
        XCTAssertTrue(oppField.waitForExistence(timeout: 5))
        oppField.tap()
        oppField.typeText("Chris Evert")

        app.buttons["newMatch.confirmStartButton"].tap()

        let pointPlayerButton = app.buttons["liveScorecard.pointPlayerButton"]
        XCTAssertTrue(pointPlayerButton.waitForExistence(timeout: 5))
        pointPlayerButton.tap()
        pointPlayerButton.tap()

        let undoButton = app.buttons["liveScorecard.undoButton"]
        XCTAssertTrue(undoButton.isEnabled)
        undoButton.tap()
    }

    // MARK: - 4. Review Statistics & Delete Video (Simulator & Device)

    @MainActor
    func testReviewStatisticsAndDeleteSeededVideo() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--uitesting-skip-onboarding", "--uitesting-seed-sample"]
        app.launch()

        // Review Statistics Tab
        app.tabBars.buttons["Statistics"].tap()
        XCTAssertTrue(app.staticTexts["Total Matches"].waitForExistence(timeout: 5))

        // Delete Seeded Video from Library
        app.tabBars.buttons["Videos"].tap()
        let deletePredicate = NSPredicate(format: "identifier BEGINSWITH 'library.deleteButton.'")
        let deleteButton = app.buttons.matching(deletePredicate).firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()

        let confirmDelete = app.buttons["Delete Video & Clips"]
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.tap()
    }

    // MARK: - 5. Physical Device Hardware Camera Test (Requires Physical iPhone 16 Pro Max)

    @MainActor
    func testPhysicalHardwareTripleLensCapture_RequiresPhysicalDevice() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical AVFoundation multi-lens hardware switching (0.5x Ultra Wide, 1x Main, 5x Telephoto) and 4K60 capture require a physical iPhone.")
        #else
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Record"].tap()
        XCTAssertTrue(app.buttons["recording.startButton"].waitForExistence(timeout: 5))
        #endif
    }
}

