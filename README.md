# OurGroceries macOS app

Native Swift implementation of a lightweight OurGroceries menu bar client.

## Repository layout

- `App/` — macOS status-item application shell and SwiftUI views.
- `Packages/GroceriesCore/` — local Swift package containing the API client and `og-dev` fixture-first developer harness.
- `Tests/OurGroceriesAppTests/` — app unit tests.
- `Tests/OurGroceriesAppUITests/` — app launch/UI tests.
- `.github/workflows/macos.yml` — macOS package and Xcode build/test gate.

Open `OurGroceriesMenuBar.xcodeproj` in Xcode and run the shared `OurGroceriesMenuBar` scheme. The application bundle identifier is `com.cjdelros.OurGroceriesMenuBar` and the deployment target is macOS 13.

Live requests must only be tested with the designated test account and list. Do not provide credentials in issues, commits, CI variables, or command-line arguments.
