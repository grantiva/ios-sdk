import SwiftUI
import Grantiva

@main
struct GrantivaExampleApp: App {
    // Replace "YOUR_TEAM_ID" with your Apple Developer Team ID.
    // On simulator, also pass an apiKey — see README for details.
    let grantiva = Grantiva(teamId: "YOUR_TEAM_ID")

    var body: some Scene {
        WindowGroup {
            ContentView(grantiva: grantiva)
        }
    }
}
