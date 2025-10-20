# Mac Installer

[README RU](./README_RU.md)

Create a one-click installer for your macOS application. Save your users from cognitive load when choosing the right file for their processor type (x86_64 or arm64), ensuring installation simplicity.

## Features

- Support for 2 source options for downloading application files: GitHub Releases and Direct URLs
- Localization in 14 languages: English, Bulgarian, Chinese (Simplified), French, German, Hindi, Italian, Japanese, Korean, Portuguese, Russian, Spanish, Turkish, Vietnamese
- The installer skips downloading application files if the app is already installed on the user's device
- Confirmation prompt when exiting the installer during download or installation

## Pre-build Setup

Navigate to the project settings and make the following changes:
1. `General` → `Display Name` — replace `AppName` with your application name
2. `Signing & Capabilities` → `Bundle Identifier` — replace `com.appname.installer` with a unique identifier for your installer

In the `AppConfig.swift` file:

1. Specify your application name in `appName` as it appears in `/Applications`
2. Choose the application file download method (`downloadType`):
   - `github` — for downloading from GitHub Releases
   - `direct` — for direct download via URL
3. Specify URLs for `latestReleaseURL`, `arm64URL`, `x86_64URL` depending on the chosen download method

In `Assets.xcassets`, replace the icon with your application's icon.

## Building the Installer

1. Navigate to `Product` → `Archive` to create a project archive
2. After creating the archive, click the `Distribute App` button, select `Direct Distribution`, and click `Distribute`
3. Wait for the process to complete and click `Export` to save the installer as a `.app` file

## Reference

- [Spotify Installer](https://download.scdn.co/SpotifyInstaller.zip)
