# fpp-AirPlayMatrix

FPP plugin that receives AirPlay video and pushes it to a Pixel Overlay matrix model.

## What it does

- Starts an AirPlay receiver (`uxplay`).
- Receives mirrored video frames from iOS/macOS.
- Scales frames to the configured FPP overlay model dimensions.
- Writes frames directly to FPP overlay shared memory for realtime matrix output.

## Requirements

- FPP 9+
- `uxplay`
- `gstreamer1.0-tools`
- `gstreamer1.0-plugins-base`
- `gstreamer1.0-plugins-good`

## Usage

1. Install plugin and dependencies.
2. Configure your matrix in FPP `Input/Output Setup -> Pixel Overlay Models`.
3. Open plugin `AirPlay Matrix - Status` page.
4. Set model name exactly to your overlay model.
5. Save config and click `Start`.
6. AirPlay mirror to the configured receiver name.

## Notes

- Video is scaled to your matrix size.
- Use flip X/Y options for panel orientation corrections.
- If startup fails, inspect `/home/fpp/media/logs/fpp-AirPlayMatrix.log`.
