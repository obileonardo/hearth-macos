# Live camera video

`LiveVideoView(entityID:muted:onState:)` shows real-time video for any Home Assistant camera
entity. It tries three things in order and reports where it got to as a `LiveState`
(`connecting`, `live(kind: "webrtc" | "hls")`, `fallbackSnapshots`, `failed`).

| Order | Path      | Used when                                         | Latency      |
|-------|-----------|---------------------------------------------------|--------------|
| 1     | WebRTC    | `camera/capabilities` lists `web_rtc`             | well under 1 s |
| 2     | HLS       | it lists `hls` and WebRTC failed or isn't offered | a few seconds |
| 3     | Snapshots | nothing else worked                               | one every 2 s |

Files: `Sources/Hearth/Views/LiveVideoView.swift` (view, model, player page) and
`Sources/Hearth/WebRTCSignalling.swift` (the Home Assistant side of a session).

## Which cameras get what

Home Assistant decides per camera (`camera/__init__.py`, `camera_capabilities`):

- A camera whose integration implements WebRTC itself (Ring, Nest) reports `["web_rtc"]` only.
  There is no HLS for these, so the fallback after WebRTC is snapshots.
- A camera with a `stream_source()` (Eufy, generic RTSP) reports `["hls"]`, plus `web_rtc` when a
  WebRTC provider such as the built-in go2rtc can play its source.

## WebRTC signalling

WebKit does the media. A `WKWebView` loads a small inline page (no network resources) with one
`<video autoplay playsinline muted>` and an `RTCPeerConnection`. Swift carries the signalling
between that page and Home Assistant's WebSocket API:

```
Swift                                    Home Assistant
  camera/webrtc/get_client_config  --->  {configuration: {iceServers: [...]}, dataChannel?}
page: new RTCPeerConnection(configuration)
      createDataChannel(dataChannel)     only if Home Assistant asked for one
      addTransceiver("audio", recvonly)  Ring needs an audio m-line in the offer
      addTransceiver("video", recvonly)
      createOffer, setLocalDescription
  camera/webrtc/offer {entity_id, offer}  --->  result (this id is now a subscription)
                                   <---  event {type: "session", session_id}
                                   <---  event {type: "answer", answer}
                                   <---  event {type: "candidate", candidate: {candidate, sdpMid?, sdpMLineIndex?}}
                                   <---  event {type: "error", code, message}
  camera/webrtc/candidate {entity_id, session_id, candidate}  --->  for each of our candidates
  unsubscribe_events {subscription}  --->  closes the session at the camera
```

Details that matter:

- Trickle ICE. The offer goes out straight away and candidates follow. Ours need the
  `session_id`, which only arrives in the first event, so earlier ones are held and sent then.
- Candidates are sent as `{candidate, sdpMid, sdpMLineIndex}`. Ring rejects candidates
  without `sdpMLineIndex`; WebKit always includes it.
- Remote candidates may arrive before the answer is applied, so the page queues them. A
  candidate with neither `sdpMid` nor `sdpMLineIndex` is added with `sdpMid: "0"`, as the
  Home Assistant frontend does.
- Unsubscribing is the only way to end a session. Home Assistant then calls the camera's
  `close_webrtc_session`, which for Ring ends the live view and lets a battery doorbell sleep.
- The page is loaded with an `https://` base URL so it is a secure context, and WebKit's ICE
  candidate filtering is turned off (a private preference, applied only if it exists) so the
  camera can see our LAN address.

## When it counts as live

Only when the `<video>` has a size and its clock has moved, that is when a frame has actually
been decoded. A connected peer with no frames is not live. If nothing arrives within 15 s
(25 s for cameras with no HLS, such as Ring, which can be slow to wake), the session is closed and
the next path is tried. A camera whose WebRTC never produced a frame skips straight to HLS
for the next 10 minutes, so the wait isn't repeated every time a window opens.

## When a live session ends

Ring limits how long a live view lasts, and any camera can drop. The page reports the end when the
connection is `failed` or `closed`, stays `disconnected` for 5 s, or receives no video bytes
for 10 s (`getStats`). Home Assistant's `error` event ends it too. If the view had been live,
it reconnects after 1, 2, 5 and 10 s, at most 4 times per appearance; after that it falls back.
The cap is deliberate, so a forgotten window can't keep a battery camera streaming.

## Teardown

`.task` cancellation and `.onDisappear` both close everything: the page calls `pc.close()`,
Swift unsubscribes, the HLS player is released and the snapshot loop stops. If the view goes
away while Home Assistant is still answering the offer, the subscription is closed the moment
the answer arrives.

## Testing without the panel

```sh
scripts/build.sh --debug
HA_URL=http://localhost:8123 HA_TOKEN=... \
  build/Hearth.app/Contents/MacOS/Hearth --live camera.front_door_live_view --capture /tmp/live
```

`--live` opens a window with just the view and logs every state change and signalling event
(`Hearth live:` in the log). `--capture <dir>` writes a decoded frame once live
(`webrtc-view.png` and `webrtc-frame.png`, or `hls-frame.png`). `--skip webrtc,hls` forces
the fallbacks.

## Known limits

- go2rtc in Docker: go2rtc's WebRTC media comes from inside the container. With bridge
  networking (and no published 18555/udp+tcp or `webrtc.candidates` setting), the Mac often
  can't reach it, so these cameras fall back to HLS after the deadline. Running Home Assistant
  with host networking, or giving go2rtc a reachable candidate, fixes that.
- Ring sessions use Ring's cloud media servers and Ring decides how long they last. Every
  session wakes the camera, which costs a battery doorbell charge.
