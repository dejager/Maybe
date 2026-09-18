# An iPhone with a healthy sense of doubt

The Maybe playground is a small, native SwiftUI app. It runs actual `.prob` programs through the Swift framework, using an explicitly simulated model provider by default. Demo mode needs no account, network, API key, or paid service. You can also connect directly to JEV with your own key.

[Watch the real JEV walkthrough](assets/maybe-jev-walkthrough.mp4), or use the [live GIF preview](assets/maybe-jev.gif). The separate [offline Demo walkthrough](assets/maybe-walkthrough.mp4) is assembled from screenshots.

## Open it

Open `Examples/MaybePlayground/MaybePlayground.xcodeproj`, select the **MaybePlayground** scheme and an iPhone simulator, then press Run. The checked-in Xcode project links to the local Swift package two directories above it. Xcode 16 or later with Swift 6 is required; the app targets iOS 17 and later.

The project disables signing for the simulator. To install on your own iPhone, enable signing in the app target and select your development team. Enter a personal JEV key through the Model sheet at runtime; do not put credentials in project files.

The editable project source is `Examples/MaybePlayground/project.yml`. If you change its structure, regenerate the checked-in project with `xcodegen generate` from that directory. You do not need XcodeGen just to open or run the existing project.

## A 30-second tour

1. Start with **Inbox**. The default message mentions “today.” The fake provider assigns a deliberately ambiguous score; an 80% confidence threshold sends the program to `otherwise maybe`.
2. Tap **Run**. A printed response appears under **Result**. Open **Decisions** to inspect the simulated scores and decision.
3. Change the input to “The launch is on fire. Urgent.” and run again. The fake's keyword rules now give the urgent label a higher score. This is a rule-based demonstration, not an evaluation of a real language model.
4. Tap the file in **Program** to open the source editor. Edit the confidence threshold or the printed text, tap Done, then run your variation. Invalid syntax gets a readable error.
5. Try **Rewrite** for a simulated rewrite, then **Chaos** for a sampled decision. Repeating chaos can choose different branches. **Replay** uses the saved effects and random draw, restores its source and input, and produces the same output without calling any provider.
6. Tap **Share Recording** to export JSON. The recording includes your source, input, generated output, effect tape, and trace. Read it before sharing it publicly.

## Native interface

The app uses system navigation, inset grouped sections, San Francisco text styles,
SF Symbols, and a bottom toolbar for Run and Replay. The source editor opens in a
standard sheet. Semantic colors follow the system's light or dark appearance;
Dynamic Type scales the content while run controls remain available in the toolbar.
At accessibility sizes, the code preview becomes a compact Edit Source row; the
full editor remains available without making the result unnecessarily far away.
An About sheet explains the demo model without crowding the main screen.

## What is real, and what is simulated?

The parser, interpreter, confidence thresholds, branching, sampling, cancellation, recording, and replay are real. In Demo mode, text generation and judgment scores come from `DemoProvider`, a small set of deterministic rules. The app adds an 850 ms cancellable delay before each fake call so the process is visible and Stop is usable. Chaos can still be random because the interpreter samples the fake distribution.

The percentages are demonstration values, not calibrated uncertainty estimates. Connecting a real model means implementing `ModelProvider` or using an appropriate backend adapter; see [the provider guide](providers.md). The demo deliberately has no API-key entry field.

## How the app is organized

- `Examples.swift`: three original programs and starting inputs.
- `PlaygroundModel.swift`: one main-actor observable model; asynchronous engine calls; recording export; a per-run UUID rejects stale event callbacks after cancellation or replacement.
- `PlaygroundView.swift`: the editable playground, output and trace. Text supports Dynamic Type, controls have VoiceOver labels, and decision bars also expose spoken percentages.
- `Probably` is the original language; `Maybe` is this Swift framework and demo. The `.prob` extension preserves language compatibility.

The app cancels active work when it enters the background. Stop retains already displayed steps/output, and cancelled or failed runs cannot be exported as complete recordings. Selecting a new example resets the run. Replay restores the last completed recording rather than pretending your unsaved edits were replayed.

## Verify it

From the repository root:

```sh
xcodebuild test \
  -project Examples/MaybePlayground/MaybePlayground.xcodeproj \
  -scheme MaybePlayground \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

Replace the simulator name with one installed on your Mac. UI tests cover running the default maybe branch, replay, opening the simulated decision trace, stopping a run, readable parser errors, an accessibility text-size run, the source-editor sheet, dark appearance, and JEV key setup/removal without making network calls. Debug-only launch arguments seed malformed source or extend fake-provider latency so error and cancellation tests are deterministic; they do not change release behavior.

For a clip, boot the simulator, run the app, and record:

```sh
xcrun simctl io booted recordVideo --codec=h264 /tmp/maybe-demo.mp4
```

Interact with the app, then press Control-C to finish the file. A short honest demo needs only the default maybe branch, its probability trace, and one replay. Keep the Demo model context visible when presenting scores.

The offline Demo clip is assembled from current simulator screenshots (light, editor, dark, result, JEV setup, replay). It is a screen-by-screen walkthrough.

## Try live JEV decisions

Tap **Model**, enter your TypeSafe API key, and select **Use JEV**. Saving makes no call. **Run** sends the program's judgment inputs and labels to JEV; usage can incur charges. **Inbox** and **Chaos** need only JEV. **Rewrite** needs a text generator, so it reports an unsupported-writing error in this example's JEV mode. It does not fall back to simulated output.

The key is session-only and is excluded from recordings. **Use Demo and Forget Key** clears it. Replay uses the recorded responses without a key or network. See the [direct JEV setup and Swift writer guide](providers.md#connect-directly-to-jev).

The standalone light/dark screenshots show Demo mode. In JEV mode, the model row, network notice, and decision-score labels identify live model estimates.

## Live walkthrough provenance

Captured 2026-09-18 from this checkout on an iPhone 18 Pro simulator running iOS 27. The user entered their key before recording began. One live Inbox request evaluated the synthetic input “Can we talk about the launch sometime today?” and returned `urgent: 0.23` and `NOT: urgent: 0.77`. The program chose its uncertainty branch, then replayed without another provider call.

The 24-second live clip uses real simulator footage, cuts idle time, and holds an actual decision-details screenshot for six seconds. Playback within the retained video segments is normal speed; the edit must not be used to infer model latency. Key entry is absent. Published PNGs have EXIF/text/time metadata removed; videos contain no source-device or location metadata.

[Live result](assets/maybe-jev-result.png) · [Offline replay](assets/maybe-jev-replay.png) · [Empty key-entry sheet](assets/maybe-jev-settings.png)
