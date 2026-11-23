# Stage 16 - Browser and Web App Scroll Fix

- Fixed the normal NEXUS browser scroll buttons to target the actual `nexus-browser` child WebView rather than an unset browser ID.
- Added up/down scroll controls to URL-based Web App panels. These controls target only that app's backing WebView (`webapp-...`), not the Windows 7 simulator or another panel.
- Made the native scroll bridge search for a scrollable container and use a document-level fallback for pages with custom scrolling layouts.

Build/device testing has not been performed in this environment.
