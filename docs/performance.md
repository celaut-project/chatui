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
