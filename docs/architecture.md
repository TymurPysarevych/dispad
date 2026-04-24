# Architecture

## Overview

`dispad` is two apps and a shared Swift package:

- **DispadHost** — macOS menu-bar app that captures the screen, encodes it, and streams it.
- **DispadClient** — iPadOS app that receives the stream, decodes it, and displays it full-screen.
- **DispadProtocol** — pure-Swift package defining the wire format shared by both.

```
┌──────────────────────┐      USB-C cable      ┌──────────────────────┐
│  Mac mini (headless) │ ◄──(usbmuxd tunnel)──► │       iPad           │
│                      │                       │                      │
│  DispadHost.app      │                       │  DispadClient.app    │
│  LaunchAgent         │                       │  Full-screen view    │
│  ScreenCaptureKit    │                       │  VideoToolbox dec    │
│  VideoToolbox enc    │                       │  AVSampleBuffer      │
│  usbmuxd server      │                       │    DisplayLayer      │
└──────────────────────┘                       └──────────────────────┘
```

## Transport

Communication runs over Apple's `usbmuxd` — the same service Xcode uses to talk to iOS devices over USB. A Peertalk-style socket carries our binary protocol on fixed port `2347`. One connection at a time.

iPads cannot accept DisplayPort video over USB-C; the port is output-only at the hardware level. All video therefore travels as encoded H.265 frames over a data channel, not as a native display signal. This also means:

- There is no output before the LaunchAgent starts (i.e. before login).
- The Mac must have a rendered display session for `ScreenCaptureKit` to capture. macOS provides a fallback virtual display when no monitor is attached; capture works against that.

## Wire format

Every message is length-prefixed:

```
[u32 length big-endian][u8 type][payload bytes...]
```

`length` includes the type byte, not itself. Payload layout depends on `type`:

| Type | Name | Direction | Payload |
|---|---|---|---|
| 1 | `hello` | Client → Host | `u16 protocolVersion`, `u16 screenWidth`, `u16 screenHeight` |
| 2 | `config` | Host → Client | HEVC VPS + SPS + PPS NALUs, concatenated in AVCC format |
| 3 | `videoFrame` | Host → Client | `u8 flags` (bit 0 = keyframe), `u64 pts`, NALU bytes (AVCC) |
| 4 | `heartbeat` | Either | empty |

Video frames use AVCC format (4-byte length prefix on each NALU) rather than Annex B start codes, because both VideoToolbox encoder and decoder prefer AVCC natively.

## Mac side pipeline

1. `ScreenCaptureKit` `SCStream` configured for the main display at 60fps, output pixel format `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange`.
2. `VTCompressionSession` with HEVC codec, real-time mode, ~15 Mbps average bitrate, 1 second keyframe interval.
3. Each encoded `CMSampleBuffer` is split into NALUs. Parameter sets (VPS/SPS/PPS) are extracted on first keyframe and on any format change, and sent as a `config` message. Each video NALU becomes a `videoFrame` message.
4. Transport server pushes messages to the single connected client. If the client disconnects, the encoder is idled until a reconnect.

## iPad side pipeline

1. Transport listener accepts one client at a time.
2. Demuxer reads length-prefixed messages and dispatches by type.
3. `config` messages set up (or reconfigure) a `VTDecompressionSession`.
4. `videoFrame` messages become `CMSampleBuffer`s and are enqueued into an `AVSampleBufferDisplayLayer`. The layer's implicit timing controls playback smoothness.

## Resolution

The Mac captures at whatever resolution macOS picks for its headless session — typically 1920×1080 on M-series Mac minis. The iPad's display layer scales the image to fit the iPad's screen. Later we can negotiate capture resolution via the `hello` message.

## Error handling

- **Client disconnects:** encoder idles, transport waits for reconnect, UI shows "Waiting for iPad…".
- **Host disconnects:** client UI shows "Disconnected, retrying…" and reconnects automatically.
- **Malformed message:** connection is closed; reconnect loop kicks in.
- **Permission denied (Screen Recording):** host surfaces a menu-bar warning with a button to open the permission pane.

## Security

MVP has no authentication — it assumes the USB link is trusted (you own both devices). For Wi-Fi in v2 we'll add a pairing step with a shared secret.
