# Osmos Banner Ads – iOS Demo (UIKit + Storyboard)

A native iOS demo app that fetches display banner ads from the **Osmos Ads** platform by Ad Unit (AU),
renders them manually in a scrollable feed, fires impression events when an ad is ≥ 50% visible, and fires
click events and opens the landing page when an ad is tapped.

| | |
|---|---|
| Language / UI | Swift, UIKit, Storyboard (`Main.storyboard`) |
| Architecture | MVVM + Repository + Service (SDK wrapper) |
| SDK | [`osmos-ios-sdk-spm`](https://github.com/onlinesales-ai/osmos-ios-sdk-spm) 3.0.1 (Swift Package Manager) |
| Concurrency | Swift async/await (no Combine) |
| Min iOS | Project deployment target (SDK itself needs iOS 15+) |

---

## 1. Setup

1. Clone the repository and open `Osmos_ads.xcodeproj` in Xcode.
2. Add the Osmos SDK package (if it isn't already resolved):
   - **File ▸ Add Package Dependencies…**
   - URL: `https://github.com/onlinesales-ai/osmos-ios-sdk-spm.git`
   - Dependency rule: **Up to Next Major Version** from `3.0.1`
   - Add the **`osmos`** library product to the **Osmos_ads** target.
   (3.x pulls in `OsmosNetworkAdCore` automatically.)
3. Select an iPhone simulator or device and press **Run** (⌘R).

SDK configuration lives in `Osmos_ads/Core/SDK/OsmosConfig.swift`:

| Key | Value |
|---|---|
| `clientId` | `10088010` |
| `productAdsHost` | `demo.o-s.io` |
| `displayAdsHost` | `demo-ba.o-s.io` |
| `cliUbid` | `Any` |
| `pageType` | `demo_page` |
| `adUnit` | `banner_ads` |

## 2. How to run the demo

1. Launch the app. The event log at the bottom already shows `SDK initialised`.
2. Tap **Load Ad**. The button shows a spinner and is disabled while the request is in flight.
3. The feed renders every creative returned in `ads.banner_ads[]`, with sample content cards in between.
   (`ads.banner_ads[0]` is the first ad in the feed.)
4. Scroll. When an ad is at least half visible you'll see `Impression Fired #n` in the event log, once per ad.
5. Tap an ad. You'll see `Click Fired` and the `destination_url` opens in an in-app Safari view.
   If a creative has no `destination_url`, which is the case for one of the demo creatives, the click is still
   tracked and the log shows `No destination_url … nothing to open`.
6. Rotate the device. The layout adapts and aspect ratios are kept. Impressions that already fired are not
   sent again.
7. To test failures, turn on airplane mode and tap **Load Ad**. The app retries automatically
   (1s, then 2s), then shows **"Ad not available"** with a **Retry** button.

Logs are also sent to the unified logging system. In the Xcode console or Console.app, filter on the category
`OsmosAds` (the iOS equivalent of Logcat).

---

## 3. Architecture

```
Osmos_ads/
├── AppDelegate.swift              SDK initialisation at launch
├── SceneDelegate.swift
├── Core/
│   ├── SDK/                       ← the ONLY place that imports `osmos`
│   │   ├── OsmosConfig.swift          client id, hosts, request params
│   │   ├── OsmosSDKManager.swift      one-time OSMOS.Builder()…buildGlobalInstance()
│   │   ├── AdServiceProtocol.swift    SDK abstraction (mockable)
│   │   └── OsmosAdService.swift       fetchDisplayAdsWithAu / registerAdImpressionEvent / registerAdClickEvent
│   ├── Analytics/
│   │   ├── AdEvent.swift              typed events (Ad Loaded, Ad Failed, Impression Fired, Click Fired…)
│   │   └── AdAnalytics.swift          fan-out to sinks: os.Logger + on-screen log
│   ├── Visibility/
│   │   └── ViewVisibilityTracker.swift  reusable 50% visibility helper
│   ├── Networking/
│   │   ├── ImageLoader.swift          async image download + NSCache
│   │   └── TrackingURLPinger.swift    fallback pinging of *_tracking_url
│   └── Errors/
│       └── AdError.swift              unified error model + retryability
├── MVVM/Main/
│   ├── Model/        BannerAd.swift, BannerAdParser.swift
│   ├── Repository/   AdRepository.swift (retry), RetryPolicy.swift
│   ├── ViewModel/    BannerAdsViewModel.swift (state machine, dedupe, impression/click rules)
│   └── View/         ViewController.swift, BannerAdView.swift, ContentCardView.swift
└── Storyboard/Base.lproj/Main.storyboard
```

**Data flow**

```
ViewController ──loadAds()──▶ BannerAdsViewModel ──▶ AdRepository (retry/backoff) ──▶ AdServiceProtocol
      ▲                              │                                                     │
      └──── onStateChange(State) ────┘                                         OsmosAdService (SDK)
                                                                                          │
                                                                       BannerAdParser ◀───┘ [String: Any]
```

* **View (Storyboard + `ViewController`)**: renders `State` (`idle`, `loading(attempt)`, `loaded([BannerAd])`,
  `failed(AdError)`). It builds the feed, connects each `BannerAdView` to the visibility tracker, and presents
  the landing page.
* **ViewModel**: allows one request at a time, records analytics, and enforces *one impression per ad* by
  keeping a set of uclids that have already fired. It sends click events without waiting for them.
* **Repository**: wraps the service with a `RetryPolicy` (3 attempts, exponential backoff 1s → 2s). Only
  transient errors (network or unknown SDK errors) are retried.
* **Service**: the only code that knows about the Osmos SDK. Everything above it uses `BannerAd`, `AdError` and
  `AdEvent.Channel`, so the SDK can be replaced or mocked.

## 4. How ad fetching works

1. `AppDelegate` calls `OsmosSDKManager.shared.initializeIfNeeded()`:
   ```swift
   OSMOS.Builder()
       .clientId("10088010")
       .productAdsHost("demo.o-s.io")
       .displayAdsHost("demo-ba.o-s.io")
       .debug(isDebugBuild)
       .buildGlobalInstance()
   ```
   A flag ensures `buildGlobalInstance()` runs only once, because a second call is a fatal error in the SDK.
   The result is then checked with `try OSMOS.shared()`.
2. **Load Ad** → `BannerAdsViewModel.loadAds()` checks the SDK again (this covers an init that failed at
   launch), changes state to `loading`, and starts a `Task`.
3. `OsmosAdService.fetchBannerAds` calls
   `adFetcher.fetchDisplayAdsWithAu(cliUbid: "Any", pageType: "demo_page", productCount: 5, adUnits: ["banner_ads"], …)`.
   Errors from the SDK's `onError` callback are captured in a thread-safe box and converted to `AdError`.
4. `BannerAdParser` reads `ads.banner_ads[]` and pulls out, for each creative:
   * `elements.value` → image URL (required, must be http/https)
   * `elements.width` / `elements.height` → aspect ratio
   * `elements.destination_url` → landing URL (optional)
   * `impression_tracking_url`, `click_tracking_url`, `uclid` (required)

   Creatives with missing or invalid required fields, or that aren't images, are skipped. An empty ad unit
   gives `noFill`. A malformed payload gives `invalidResponse`.
5. `BannerAdView` downloads the image (`ImageLoader`, cached and decoded off the main thread). An aspect-ratio
   constraint `height = width × (height/width)` keeps the creative's proportions in any orientation. Height is
   capped at 320pt so small square creatives aren't scaled up to fill the screen. If the response has no size,
   the real image size is used.

## 5. How impression logic works (50% visibility)

`ViewVisibilityTracker` is a standalone, reusable helper:

```swift
tracker.track(adView, threshold: 0.5) { /* called exactly once */ }
```

* **Measurement**: `visibleFraction(of:)` converts the view's bounds to window coordinates. It then walks up
  the superview chain and intersects with every ancestor that has `clipsToBounds` set (the scroll view clips
  its content), and finally with the window bounds. The visible area divided by the full area is the
  fraction. The result is 0 if the view or any ancestor is hidden or transparent, the view isn't in a window,
  or the scene isn't `foregroundActive`, so nothing is counted while the app is in the background or the
  app switcher.
* **Triggers**: KVO on the scroll view's `contentOffset` and `bounds` (scrolling and rotation),
  `viewDidLayoutSubviews`, rotation completion, and `UIScene.didActivateNotification` (returning to the
  foreground).
* **Once per ad**: the tracker removes a registration *before* calling its handler, so a handler can't fire
  twice. The ViewModel also keeps a set of uclids that have fired. This means a re-layout, rotation or second
  scroll pass never sends a duplicate impression.
* An ad is only registered with the tracker **after its image has rendered**, so a placeholder or failed
  creative never counts as an impression.
* The event is sent with `registerEvent.registerAdImpressionEvent(cliUbid:uclid:position:onError:)`, where
  `position` is the ad's 1-based slot in the feed.

## 6. How click tracking works

1. `BannerAdView` only accepts taps once it has rendered successfully.
2. `BannerAdsViewModel.adWasTapped(_:)` sends
   `registerEvent.registerAdClickEvent(cliUbid:uclid:trackingParams:onError:)` without waiting for it. The
   Osmos click API is designed this way, so navigation isn't held up by tracking.
3. If `elements.destination_url` is valid, it opens in an `SFSafariViewController`, so the user stays in the
   app. If it's missing, the click is still tracked and the gap is logged.

**Fallback**: if the SDK's `registerEvent()` is unavailable, `OsmosAdService` sends a GET request to the
`impression_tracking_url` / `click_tracking_url` from the response, so tracking still works. The event log
shows which path was used (`via SDK` or `via tracking URL`).

## 7. Event logging / analytics

`AdAnalytics.track(_:)` sends typed `AdEvent`s to pluggable `AnalyticsSink`s:

| Event | When |
|---|---|
| `sdk_initialized` / `sdk_init_failed` | App launch, or retried on Load Ad |
| `ad_requested`, `ad_retry_scheduled`, `ad_request_duplicate_ignored` | Fetch lifecycle |
| **`ad_loaded`** / **`ad_failed`** | Fetch result |
| `ad_rendered` / `ad_render_failed` | Image download per creative |
| **`impression_fired`** / `impression_failed` | ≥ 50% visible, once |
| **`click_fired`** / `click_failed`, `landing_page_opened` / `landing_page_missing` | Tap |

Sinks: `OSLogAnalyticsSink` (Xcode console / Console.app) and a block sink that drives the **on-screen
Event Log**. Recent events are replayed to sinks added later, so the init event logged before the UI existed
still appears on screen. A remote analytics backend would be one more sink.

## 8. Error handling and resilience

| Case | Behaviour |
|---|---|
| SDK init failure | Logged at launch; re-attempted on **Load Ad**; UI shows *"Ad not available"* + **Retry** |
| Network error | Retried automatically (3 attempts, exponential backoff), then *"Ad not available"* + **Retry** |
| No ads in response | Not retried; *"Ad not available"* |
| Invalid / missing fields | Bad creatives skipped; if none are valid → *"Ad not available"* |
| Image download fails | That slot shows *"Ad not available"*; no impression or click possible |
| Missing `destination_url` | Click tracked, nothing opened, logged |

There are no force unwraps of response data, and every parse is defensive (numbers as `Int`, `Double` or
string; the literal `"null"`; non-http URLs).

## 9. UX, lifecycle and rotation

* **Loading state**: the button's built-in activity indicator, "Loading…" or "Retrying… (attempt n of 3)",
  plus per-ad spinners while images download.
* **Duplicate requests**: the button is disabled while loading, and the ViewModel ignores `loadAds()` if a
  task is already running (and logs it).
* **Lifecycle**: the load task is cancelled when the ViewModel is deallocated. Impressions are suppressed
  while the scene isn't active and re-checked when it becomes active again. Image tasks are cancelled when
  their views are released.
* **Rotation**: on iOS the view controller isn't recreated on rotation (unlike Android's Activity), so state
  is kept in the ViewModel automatically. Auto Layout and the aspect-ratio constraints adapt the feed, the
  event log shrinks in compact height (landscape iPhone), and visibility is re-checked after the transition.

## 10. Assumptions

* `cliUbid = "Any"` is used as given. A production app would use a stable, privacy-safe user id.
* "Load multiple ads" is done with **one request** for `banner_ads` with `productCount = 5`, rendering every
  returned creative. The demo account usually returns 1–3 creatives. Content cards are placed between ads so
  they start off-screen and the 50% rule actually matters.
* Only `IMAGE` creatives are rendered manually; video and HTML creatives are skipped.
* An impression is counted the first moment 50% is visible (no minimum time on screen), as the brief asks. A
  minimum duration (e.g. MRC's 1 second) could be added to the tracker.
* If an impression call fails, it isn't retried, so the "once per ad" rule holds. The failure is logged.
* The SDK's batching/retry options for events aren't enabled. Events are sent right away for clear demo logs.

## 11. Challenges faced

* **Response shape**: the SDK returns an untyped `[String: Any]`, and the documentation examples show several
  formats (`value` vs `mobile_image`, `destination_url` vs `destination`). The parser handles all of them and
  validates each field.
* **Missing landing pages**: one of the demo creatives has no `destination_url`. Clicks on it are still tracked
  and the missing URL is reported instead of crashing or opening a blank page.
* **Accurate visibility inside a scroll view**: comparing frames to the screen isn't enough. Scroll-view
  clipping, hidden ancestors and the scene's activation state all need checking, which is why the tracker
  clips through the whole superview chain.
* **Swift concurrency with a callback-based SDK**: the target uses MainActor default isolation, but the SDK may
  call `onError` on any thread. The service layer is `nonisolated`, uses `@Sendable` closures, and stores
  errors in a `Mutex`, and only `Sendable` models (`BannerAd`) cross back to the main actor.
* **`buildGlobalInstance()` being fatal if called twice**: guarded by a one-time flag so retrying init is safe.
