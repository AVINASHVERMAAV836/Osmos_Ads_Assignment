**Subject: iOS Developer Assignment – Osmos Banner Ads Demo App**

# Osmos Banner Ads – iOS Demo

A native iOS app (Swift, UIKit, Storyboard) that fetches banner ads from Osmos Ads, shows them in a scrollable feed, fires an impression when an ad is at least 50% visible, and fires a click event when an ad is tapped.

- **Architecture:** MVVM + Repository + Service
- **SDK:** [osmos-ios-sdk-spm](https://github.com/onlinesales-ai/osmos-ios-sdk-spm) 3.0.1 (Swift Package Manager)
- **Concurrency:** async/await

---

## 1. Setup

**Requirement:** Xcode **27.0** is required to build and run this project.

1. Clone the repo and open `Osmos_ads.xcodeproj` in Xcode 27.0.
2. If the SDK is not already resolved: **File ▸ Add Package Dependencies…** and use
   `https://github.com/onlinesales-ai/osmos-ios-sdk-spm.git` (from `3.0.1`). Add the `osmos` product to the `Osmos_ads` target.
3. Pick a simulator or device and press **Run** (⌘R).

Configuration is in `Core/SDK/OsmosConfig.swift`:

| Key | Value |
|---|---|
| clientId | `10088010` |
| productAdsHost | `demo.o-s.io` |
| displayAdsHost | `demo-ba.o-s.io` |
| cliUbid | `Any` |
| pageType | `demo_page` |
| adUnit | `banner_ads` |

## 2. How to run the demo

1. Launch the app. The event log shows `SDK initialised`.
2. Tap **Load Ad**. A loading state shows and the button is disabled.
3. Banner ads appear in a scrollable feed, with sample cards in between.
4. Scroll. When an ad is half visible, the log shows `Impression Fired` (once per ad).
5. Tap an ad. The log shows `Click Fired` and the landing page opens in an in-app Safari view.
6. Rotate the device. The layout adapts and impressions are not sent again.
7. To test errors, turn on airplane mode and tap **Load Ad**. The app retries, then shows **"Ad not available"** with a **Retry** button.

Logs also go to the Xcode console under the category `OsmosAds` (the iOS equivalent of Logcat).

## 3. Demo

**Demo video:** [Add video link here]

The short recording shows:

1. **Ad loading:** tapping **Load Ad**, with the loading state.
2. **Banner rendering:** ads shown in the scrollable feed with the correct aspect ratio.
3. **Impression firing:** `Impression Fired` in the log when an ad is 50% visible (only once per ad).
4. **Click handling:** `Click Fired` in the log and the landing page opening.
5. **Error scenarios:** airplane mode, retries, and the "Ad not available" message with **Retry**.

The app source is in this repo (`Osmos_ads.xcodeproj`).

## 4. Architecture

```
Osmos_ads/
├── AppDelegate.swift          SDK init at launch
├── Core/
│   ├── SDK/                   Only place that imports the SDK (config, manager, service)
│   ├── Analytics/             Event types + logging (console and on-screen log)
│   ├── Visibility/            Reusable 50% visibility tracker
│   ├── Networking/            Image loader + tracking-URL fallback
│   └── Errors/                AdError
├── MVVM/Main/
│   ├── Model/                 BannerAd, BannerAdParser
│   ├── Repository/            AdRepository (retry with backoff)
│   ├── ViewModel/             BannerAdsViewModel (state, no duplicate requests/impressions)
│   └── View/                  ViewController, BannerAdView, ContentCardView
└── Storyboard/Main.storyboard
```

**Flow:** `ViewController → ViewModel → Repository (retry) → Service (SDK) → Parser → UI`

- **View:** shows the current state (idle, loading, loaded, failed).
- **ViewModel:** allows one request at a time and makes sure each ad fires only one impression.
- **Repository:** retries failed requests (3 attempts, 1s then 2s delay).
- **Service:** wraps the SDK so it can be replaced or mocked.

## 5. How ad fetching works

1. At launch the SDK is initialised once with the client ID and hosts above.
2. Tapping **Load Ad** calls `fetchDisplayAdsWithAu` with `cliUbid = "Any"`, `pageType = "demo_page"`, `adUnit = "banner_ads"`.
3. The parser reads `ads.banner_ads[]` and extracts:
   - `elements.value` → image URL
   - `elements.destination_url` → landing URL
   - `impression_tracking_url`, `click_tracking_url`
4. Ads with missing or invalid fields are skipped. If nothing valid remains, the UI shows **"Ad not available"**.
5. The image is downloaded and shown with its width/height ratio so the aspect ratio is preserved.
6. If the SDK request times out, the app falls back to calling the same API endpoint directly.

## 6. How impression logic works (50% visibility)

`ViewVisibilityTracker` is a reusable helper:

```swift
tracker.track(adView, threshold: 0.5) { /* called once */ }
```

- It calculates the visible part of the ad inside the scroll view and the screen.
- It re-checks on scroll, rotation, layout changes and when the app returns to the foreground.
- Nothing is counted while the app is in the background.
- The ad is only tracked after its image has loaded.
- **Once only:** the tracker removes the ad before firing, and the ViewModel also remembers which ads already fired.
- The event is sent with `registerAdImpressionEvent`.

## 7. How click tracking works

1. A tap is accepted only after the ad image has rendered.
2. `registerAdClickEvent` is sent from the SDK (without blocking the UI).
3. `elements.destination_url` opens in an in-app Safari view. If there is no URL, the click is still tracked and the log notes it.
4. If the SDK is unavailable, the `click_tracking_url` from the response is called instead.

## 8. Event logging

Logged events: **Ad Loaded, Ad Failed, Impression Fired, Click Fired** (plus a few extras such as retry and render events). They appear in the Xcode console and in the on-screen Event Log.

## 9. Error handling

| Case | Result |
|---|---|
| SDK init fails | Logged; retried on **Load Ad**; shows "Ad not available" |
| Network error | Auto-retry, then "Ad not available" + **Retry** |
| No ads in response | "Ad not available" |
| Missing or invalid fields | Bad ads skipped, no crash |
| Image fails to load | That slot shows "Ad not available" |
| Missing `destination_url` | Click tracked, nothing opened |

Other UX: loading state while fetching, duplicate requests blocked, and rotation handled (state is kept in the ViewModel).

## 10. Assumptions

- `cliUbid = "Any"` is used as given.
- Multiple ads come from one request (`productCount = 5`). The demo account usually returns 1–3 ads.
- Only image ads are rendered. Video and HTML ads are skipped.
- An impression counts as soon as 50% is visible (no minimum time).
- A failed impression is not retried, to keep "once per ad".

## 11. Challenges faced

- **Unclear response format:** the SDK returns untyped data and field names vary, so the parser searches for `ads.banner_ads` and validates every field.
- **Missing landing URL:** one demo ad has none, so clicks are still tracked and handled safely.
- **Accurate visibility in a scroll view:** the tracker accounts for clipping, hidden views and app state.
- **SDK callbacks and Swift concurrency:** handled with a thread-safe service layer.
- **SDK timeout (~5s) on slow networks:** solved with the direct API fallback.
- **`buildGlobalInstance()` crashes if called twice:** guarded with a one-time flag.
