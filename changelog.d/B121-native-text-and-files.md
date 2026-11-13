### Added
- On iOS the two fields are the system's: a native text field with the real edit menu (one localized `Paste`, no AutoFill), a native document picker that reaches Files and iCloud, and a zip shared from Files opens the app and imports.
- A link install downloads through `NSURLSession`, so a 302 to a release-assets host is followed instead of being read as a failed request.

### Fixed
- The plugin class name is `LethebarNative`, so the bridge is found on the device.
- The pending path is a `std::string`, so the image initializer no longer calls engine strings before they are bound.
- Installing a layer returns to the pack page instead of starting the layer at its entry; the kind is read from the installed manifest.
