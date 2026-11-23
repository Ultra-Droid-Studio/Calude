# Stage 14 — WebView snapshot performance and gaze input

Changes based on Stage 13:
- Snapshot capture cadence reduced from 280 ms to 600 ms (about 1.7 snapshots/second per active web panel).
- Virtual backing WebView resolution capped at 1280x800 and device scale capped at 1.0.
- Snapshot bitmap is scaled to at most 960x600 and encoded as JPEG quality 58 instead of full-resolution PNG. This reduces bitmap memory, base64 traffic, and decode/texture upload work.
- Gaze interaction no longer converts the top and bottom 8% of a web page into scroll-only zones. A gaze dwell at those coordinates now dispatches a real touch, so controls near page edges can be activated.
- The original Windows 7 HTML and browser engine are preserved; no canvas-only recreation was substituted.

Validation:
- `node --check` passed for the main inline JavaScript.
- ZIP integrity checked after packaging.
- Android Gradle build could not be run in this environment: the wrapper JAR is absent and downloading it failed due unavailable network DNS. Real-device performance and touch behavior still need validation on AndroidIDE/device.
