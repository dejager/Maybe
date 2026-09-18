# Give Maybe a brain

The interpreter knows how to branch. A provider supplies the words and the judgments. Swapping one does not change your program's syntax.

```swift
import Maybe

public protocol ModelProvider: Sendable {
    func write(prompt: String, context: Value?) async throws -> String
    func judge(value: Value, labels: [String]) async throws -> [String: Double]
}
```

`Value` is a string, number, or Boolean. Return one probability per supplied label; every number must be finite and in `0...1`. The total must be within `0.02` of one. Maybe normalizes that small rounding error before choosing a branch. Labels are literal strings, including `NOT: urgent`; preserve them exactly. Empty label strings are legal in the language and must also be preserved; the label list itself must contain at least one distinct choice. Missing labels, invalid numbers, and totals outside the tolerance fail the run. Probabilities supplied by a model are not automatically calibrated measurements.

## Start with the demo

```swift
let engine = Maybe(provider: DemoProvider())
```

This uses **no model and no network**. The numbers are scripted demonstration scores, not predictions. The rules are deliberately small enough to read:

| Label contains | Input contains | Positive score |
| --- | --- | --- |
| `urgent` | `urgent`, `asap`, `emergency`, `on fire`, `down`, or `immediately` | 0.94 |
| `urgent` | otherwise `maybe`, `soon`, `might`, `whenever`, or `today` | 0.52 |
| `urgent` | otherwise | 0.06 |
| `jargon` or `corporate` | a jargon term listed below | 0.95; otherwise 0.05 |
| `clear`, `simple`, or `plain` | `leverage`, `synerg`, `paradigm`, `utilize`, or `operationalize` | 0.10; otherwise 0.90 |
| anything else | the full label phrase appears in the input | 0.90; otherwise 0.50 |

Matching ignores case and uses substrings. Rules are checked in table order. A `NOT:` prefix complements the positive score; all label scores are then normalized together. For an `urgent`/`NOT: urgent` pair, “Can we talk about the launch sometime today?” therefore lands at 0.52, a useful way to see the `maybe` branch. This intentionally simple heuristic will misread ordinary language, including negation.

Writing replaces `leverage` → `use`, `synergies`/`synergy` → `teamwork`, `paradigm` → `approach`, `utilize` → `use`, `circle back` → `talk again`, `move the needle` → `make progress`, `stakeholders` → `people involved`, `bandwidth` → `time`, and `operationalize` → `put into practice`. With nothing to replace, it prefixes the context with `Demo draft:`. Without context, it uses the prompt as its source text. It does not follow arbitrary instructions.

## Connect an existing Swift service

`ClosureProvider` is the shortest bridge to your own app service:

```swift
let provider = ClosureProvider(
    write: { prompt, context in
        try await writingService.generate(instruction: prompt, context: context)
    },
    judge: { value, labels in
        try await judgmentService.probabilities(for: value, labels: labels)
    }
)
let engine = Maybe(provider: provider)
```

The service names above are placeholders for your own implementations. Both closures are `@Sendable`: use an actor or another safely shared service. Both must cooperate with task cancellation. The wrapper checks cancellation before and after each closure, but cannot forcibly terminate arbitrary code. The interpreter validates returned judgments. If your local model cannot supply meaningful probabilities, document that limitation rather than asking it to invent a percentage and calling it confidence.

## Put an app backend between iOS and paid models

```swift
let provider = try ProxyProvider(
    endpoint: URL(string: "https://your-app.example/api/maybe")!,
    bearerToken: shortLivedUserToken
)
let engine = Maybe(provider: provider)
```

The URL above is illustrative; this repository does not deploy a backend. `bearerToken` is an app user session token, **not** a JEV key. The initializer requires HTTPS and rejects embedded URL credentials and fragments. Create a new provider when your session token refreshes.

The contract is two operations on one endpoint. Requests use `POST`, `Content-Type: application/json`, `Accept: application/json`, and `Authorization: Bearer <user-token>`.

Writing request:

```json
{"operation":"write","prompt":"Rewrite in plain English","context":"Leverage synergies."}
```

Writing response, HTTP 200:

```json
{"text":"Work together."}
```

`context` is always present and may be a JSON string, number, Boolean, or `null`. Response text must be a nonempty string after trimming whitespace.

Judgment request:

```json
{"operation":"judge","value":"The website is down","labels":["urgent","NOT: urgent"]}
```

Judgment response, HTTP 200:

```json
{"probabilities":{"urgent":0.94,"NOT: urgent":0.06}}
```

`value` is a JSON string, number, or Boolean. Return the exact label keys. Probabilities follow the validation rules at the top of this guide; additional response fields are ignored. Return an appropriate non-2xx status for authentication, quota, or upstream failures. The client intentionally does not display server error bodies because they may contain prompts or credentials.

Your backend is responsible for verifying the user token, enforcing per-user budgets and rate limits, selecting permitted models, storing provider keys, and deciding what input/output to log. Apply body-size limits and validate these schemas there, too. Preserve the distinction between instructions and context when constructing model requests. The client cannot enforce server-side billing or authorization.

## Connect directly to JEV

```swift
let provider = try JevProvider(apiKey: userSuppliedAPIKey)
let engine = Maybe(provider: provider)
let result = try await engine.run(
    #"if input() feels "urgent" { print("Take a look.") } else { print("It can wait.") }"#,
    input: "The checkout is down."
)
```

Get a key from the [TypeSafe console](https://console.typesafe.ai/settings/keys). `apiKey:` is the only required setting; `model:` defaults to `jev-latest` and can pin a specific JEV version. No gateway account or gateway token is needed. The library never reads your environment, Keychain, or files.

In the **iPhone playground**, tap **Model**, enter your own key, and choose **Use JEV**. Saving settings makes no request; **Run** sends input and decision criteria directly to TypeSafe. The key stays in memory until you replace it, choose **Use Demo and Forget Key**, or terminate the app. It is never written to settings or recordings. Cancelling the sheet leaves the existing connection unchanged. Switching connections clears the previous result so simulation and live decisions cannot be confused. If your own app needs persistent personal keys, use Keychain; do not embed a shared developer key in an app bundle.

For the **CLI**, set `JEV_API_KEY` in the process environment (`TYPESAFE_API_KEY` is also accepted; `JEV_API_KEY` takes precedence). `JEV_MODEL` optionally overrides the model. In macOS's default zsh, enter a key without placing it in command history:

```sh
read -s 'JEV_API_KEY?JEV API key: '
export JEV_API_KEY
swift run maybe run Examples/Programs/inbox.prob --input "The checkout is down." --live --trace
unset JEV_API_KEY
```

The CLI does not load `.env` files automatically. Live calls require `--live` and can incur charges. Replay never needs a key or a network connection.

### Decisions and text generation

JEV evaluates choices; it does not generate text. **Inbox** and **Chaos** work with JEV alone. **Rewrite**, and any reached `llm` expression, require a separate writer. Without one, `JevProvider` throws a clear error; it never silently substitutes demo output. The live CLI and playground intentionally have no text generator configured.

A writer is just an asynchronous Swift function supplied by your application:

```swift
let provider = try JevProvider(apiKey: userSuppliedAPIKey, write: { prompt, context in
    try await writingService.generate(instruction: prompt, context: context)
})
```

`writingService` is a placeholder for your implementation. It could call an on-device model, a hosted model, or your own service. **Maybe does not bundle a local AI model.** The function must be `@Sendable`, honor cancellation, and return nonempty text. Its authentication is managed separately from the JEV key.

### HTTP contract

Judgments use `POST https://api.typesafe.ai/v1/systemone` with `Authorization: Bearer <key>`. The JSON body contains `model`, `state: {"value": ...}`, and a `questions.decision` Choice question. Criteria use stable `option_0`, `option_1`, … keys to preserve arbitrary language labels. The adapter reads `answers.decision.probabilities` and maps them back to the original labels, validating the distribution. More than 255 choices are rejected before sending.

Probably's `with confidence` syntax thresholds the **label probability**. JEV's separate answer `confidence` field is not used; changing that would change the language. Score and Noul primitives are not exposed by this adapter.

Checked against the official [HTTP reference](https://docs.typesafe.ai/api), [Choice documentation](https://docs.typesafe.ai/primitives/choice), and [model introduction](https://docs.typesafe.ai/introduction) on 2026-09-18. A direct Inbox judgment was verified with a real credential on 2026-09-18, followed by offline replay. That single smoke test does not establish model accuracy or ongoing availability.

### Migrating from the first prototype

`CloudflareJevProvider` has been removed. Replace its initializer with `JevProvider(apiKey:)`; remove `CF_ACCOUNT_ID`, `CF_API_TOKEN`, `GATEWAY_ID`, and `TEXT_MODEL` from your setup. If your workflow generates text, supply `write:` explicitly. Existing recordings still replay offline.

## Networking and testing

The built-in transport uses an ephemeral `URLSession`, 25-second request and resource timeouts, no persistent cookies or disk cache, and refuses redirects so credentials stay at the selected endpoint. Responses are read incrementally and capped at 1,000,000 bytes. HTTP status, JSON shape, nonempty text, and judgment probabilities are checked. Cancellation remains `CancellationError`; server bodies and underlying transport error details are redacted. The library does not automatically retry billable calls.

Inject an `HTTPTransport` to exercise the real adapter without spending money:

```swift
let transport = HTTPTransport { request, maximumBytes in
    let data = Data(#"{"text":"Hello from a fixture."}"#.utf8)
    let response = HTTPURLResponse(
        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
    )!
    return (data, response)
}
let provider = try ProxyProvider(
    endpoint: URL(string: "https://example.invalid/maybe")!,
    bearerToken: "test-only",
    transport: transport
)
```

A custom transport must honor cancellation, the request deadline, and the supplied byte limit while downloading. The adapter also checks the returned buffer size, but cannot undo an oversized allocation made by custom code. Tests cover the request schemas, direct JEV authentication and label mapping, malformed and oversized payloads, HTTP failures, cancellation, timeout handling, normalization, and redaction. They verify the protocol implementation, not a provider's model quality or live availability.
