# Performance of navigation

`app/integration_test/navigation_perf_test.dart` times the moves between the pages of
the app on a device or an emulator. `app/test_driver/perf_driver.dart` writes the results.
This note says how to run it and what it found in October 2026.

## 1. What the test does

The test starts the app and makes each move four times (`PERF_ROUNDS`):

| Trace | Moves |
|---|---|
| `tabs_first` | Each tab of the bottom bar, the first time it shows |
| `tabs` | Chats, Wallet, Compute, Settings, again and again |
| `conversation` | A conversation that runs, its info page from the bar, back, back |
| `new_conversation` | The pencil button, back |
| `wallet_page` | The page of the wallet from the Wallet tab, back |
| `compute_pages` | Nodes and Services from the Compute tab, back |
| `settings_pages` | Security, Network and Tor, Nodes and About from the Settings tab, back |
| `launch_rocket` | The rocket of a launch over the Chats tab: it hovers for 2 s, then lifts off. No launch, nothing spent |

Each trace gives a timeline summary: the frames, the build and raster time of each frame,
and the frames over the budget of 16 ms. For each move, the test also takes the time from
the tap to the first frame that has the new page.

The test skips `conversation` when no conversation runs, and `wallet_page` when the app
has no wallet. It reads what the app has: it does not start, stop or delete an instance,
and it does not spend.

## 2. How to run it

Use profile mode: debug mode builds frames much more slowly, so its numbers say little. An
emulator draws with the CPU (SwiftShader), so its raster times are much higher than those
of a phone. Compare two builds on the same device, under the same load.

1. On the device, have one wallet, one node and one conversation that runs.
2. Build the test as an APK:

   ```sh
   cd app
   flutter build apk --profile --target-platform android-x64 \
     --target=integration_test/navigation_perf_test.dart
   ```

   For a phone, use `--target-platform android-arm64`.
3. Run it. `--keep-app-running` matters: without it, `flutter drive` uninstalls the app at
   the end, with its wallet and its Celaut database.

   ```sh
   flutter drive --profile --no-dds --keep-app-running \
     --use-application-binary=build/app/outputs/flutter-apk/app-profile.apk \
     --driver=test_driver/perf_driver.dart \
     --target=integration_test/navigation_perf_test.dart -d <device>
   ```

   `--no-dds` lets the test connect to the VM service for the timeline.
4. Read `build/<trace>.timeline_summary.json` and `build/navigation_latency.json`.
   `build/<trace>.timeline.json` opens in `chrome://tracing` or Perfetto.

The APK of the test has the same package name and the same debug key as the debug build
of the app, so it installs over the app and keeps its data.

## 3. What it found (October 2026)

The setup: AVD `chatui-x86` (Android 15, x86_64, SwiftShader, 1080 × 2400), profile builds,
the app at 0.1.13, our node on the same host, two runs of each build. On SwiftShader a
frame of a plain page takes about 18 ms to raster, so most frames miss the budget of 16 ms
before and after; the slow frames below are the ones of 0.1 s and more.

**The cause: the scene of the home pages, painted again on each frame.** Build times were
small: under 2 ms on average. Raster times were not. The scene behind the overview, the
Compute tab and the page of the wallet (`HomeScene`) has blurred strokes: the glow of the
eclipse and the light along the crests. Impeller draws each blur in an offscreen render
pass. The traces with the scene had 80 to 500 render passes a frame, and new textures on
many frames; the traces without it had 1 render pass a frame. The scene did not change,
but the page painted it again on each frame of a route transition over it or under it, and
on the switch of a tab. On the emulator, such a frame took 0.7 to 1.1 s. The transition of
450 ms then showed one or two frames, and the next page came after more than a second.

**The fix:** `SceneImagePainter` paints the scene once into an image, for its size and its
look, and then draws the image. The image looks the same: in the render tests, no pixel
differs by more than 6 of 255. The app keeps four images at most, about 6 MB each on a
1080-pixel-wide screen.

| Move: tap to the first frame of the page | Before, median (max) | After, median (max) |
|---|---|---|
| Compute tab | 644 ms (674) | 36 ms (48) |
| Settings tab | 674 ms (707) | 26 ms (41) |
| Compute tab, first time | 1280 ms (1300) | 466 ms (469) |
| Page of the wallet | 659 ms (922) | 29 ms (39) |
| Compute → Nodes | 1370 ms (1453) | 44 ms (53) |
| Compute → Services | 1367 ms (1454) | 50 ms (58) |

The first time the Compute tab shows, the app makes the image: that frame is still slow.

**A conversation opened only once the tunnel to its chat slot was open.** The tap showed
nothing until then. On the emulator the node is on the same host, and the tunnel took 40
to 700 ms; a far node or Tor takes longer. The page now shows at once, with a spinner, and
the conversation follows in place.

**Checked, and not a cause here:**

- The synchronous calls to the core (`celaut_instances`, `celaut_known_nodes` and the
  others) read the database in memory. They do no I/O.
- The tabs are built the first time they show, then kept. A rebuild of the home screen
  costs about 1 ms.
- The catalog of skills is cached in the core. The list of nodes checks the nodes after it
  shows; the move does not wait for the check.

## 4. The improvements of 2026-10-23

Same setup, two runs of each build: master (`39d8ba8`) and the branch of the improvements
(rocket, robots, filter, Settings in three sections, the wallet without a name). Our node
on the same host, one conversation running, a host load of 6 to 14.

- **No move got slower.** Every trace had the same frames, build and raster times as
  master, within the spread of two runs (for example, `tabs` raster 19.2 → 20.1 ms on
  average, `settings_pages` 19.6 → 19.6 ms; no frame over 100 ms outside `tabs_first`,
  which has the 3 slow frames it had before).
- **The rocket** (`launch_rocket`, new): 270 frames, 1 render pass a frame and one
  texture in the whole trace, raster 19.4 ms on average and 28 to 38 ms at worst. It costs
  what a plain page costs on SwiftShader.

## 4. Web instances: slow or never loading (October 2026)

Pages of web instances (the browser on `127.0.0.1:<port>`, one tunnel stream per TCP
connection) loaded very slowly or not at all, most of all through Tor. The causes, and the
fixes:

1. **The dial limit was 10 s on every route** (`celaut-wire/src/channel.rs`,
   `ConnectOptions::default`). A route through Tor needs a circuit, the TLS handshake and
   the HTTP/2 setup: several round trips of 0.3 to 1 s. The first connection failed, and
   the page with it. Now `default_connect_timeout()` gives 60 s on a SOCKS route and 10 s
   on a direct one.
2. **HTTP/2 windows of 64 KiB** (tonic default). One stream could carry 64 KiB per round
   trip, about 128 KiB/s at an RTT of 0.5 s, and the 64 KiB window of the connection was
   shared by all the streams, so the 6 or more connections of a browser stalled each other
   (head-of-line blocking). Now 4 MiB per stream and 16 MiB per connection.
3. **No HTTP/2 PING.** A connection that died with no FIN or RST (the phone changed from
   Wi-Fi to mobile data, a circuit of Tor closed) stayed "open" until the TCP
   retransmission timeout, minutes later, and every stream on it hung. Now a PING goes
   every 30 s while a call is open, and a connection with no answer in 25 s is dropped;
   tonic then dials again for the next stream. No PING goes on an idle connection.
4. **A stream that failed to open closed the browser connection** (`celaut-client/src/
   local_port.rs`). The first error (no connection, `Unavailable`) reset the page. Now the
   relay opens the stream again, up to 3 times with a wait of 0.25, 0.5 and 0.75 s, and
   sends again the bytes that it already sent (up to 1 MiB), as long as no byte came back.
   Only a stream that never opened is opened again (no connection, a time limit, or a
   failure before any byte of the request went out): an error after the request was sent
   (`Unavailable`, a keepalive that timed out) ends the connection, because the service
   may have run the request. A refusal of the node (token, balance, slot) is not retried.

### HTTP over the tunnel with no local port (`celaut-client/src/http_tunnel.rs`)

`HttpTunnel` sends HTTP/1.1 requests to a slot of an instance through the `ServiceTunnel`
and gives back status, headers and body. It listens on nothing, so no other process can
reach the instance through it. What the node charges:

- **One `TUNNEL_OPEN_MU` per stream, and one stream per `HttpTunnel`**, not per request or
  per resource: the requests go one after the other on the same stream (keep-alive).
  `streams_opened()` counts the opens. The stream opens with the first request.
- **Another open** when the stream is closed: the service closed the connection
  (`Connection: close`, an idle timeout of the service), the node dropped the stream, a
  request failed or timed out, or a streamed body was dropped before its end. A stale
  stream found closed before a request costs one open.
- **A request is sent again only when it surely never reached the service**: nothing of it
  was written, or the stream failed to open (no connection, a time limit) before any byte
  came back (up to 3 more opens, as the local port). A request that went out on a stream
  that then failed is not sent again, so the service never runs it twice (PR #77). The
  caller decides whether to repeat it.
- The bytes of the requests and answers are charged as for the local port; the HTTP
  framing adds a few hundred bytes of headers per request.

Limits (`Limits`, defaults in the module): head of an answer 64 KiB and 100 headers, body
64 MiB (a `Content-Length` over it fails before the body is read), 120 s to the head of
the answer, 60 s with no byte of the body. A request over a limit fails with an error and
closes the stream. The requests are serialized, so a slow answer holds the next request:
a page that loads many resources in parallel gets them one at a time on one stream. Not
verified against a real node.

Dart reaches it through `api/celaut_http.rs` (step 2 of #79): `celautHttpOpen(instanceId,
slot)` gives a handle (a number that is never reused; the token stays in Rust),
`celautHttpRequest(handle, method, pathAndQuery, headers, body)` gives the whole answer
(status, headers, body), and `celautHttpClose(handle)` drops the tunnel and its stream
(closing twice is fine; a request on a closed handle is an `InvalidInput` error). Close the
handle when the page closes: the table of handles holds the tunnel until then, or until the
instance is stopped or deleted. Answers with a streamed body are not exposed yet.

Not changed: the Dart `TunnelHttp` is only for the chat calls, and the web page opens in
the system browser, so neither limits the page. `SOCKS_CHECK_TIMEOUT` (5 s) is for the
local proxy, not for the circuit.

Unverified here: the real effect through Tor (no Tor or node in the build host). To check:
open a web instance on a node by an onion address and compare the time of the first
paint, before and after. A node that closes a connection for PINGs every 30 s would show
as `Unavailable` in `last_error`; then raise `KEEP_ALIVE_INTERVAL`.
