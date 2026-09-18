# Public release checks

Checked 2026-09-18. This records verification scope, not a guarantee that a scanner can find every secret.

## Repository hygiene

- Gitleaks 8.30.0 scanned the working files and every reachable commit after fetching remote branches/tags. No secrets were detected.
- A separate scan checked text files for personal home-directory paths, email addresses, and private-key headers. No personal filesystem paths were found in the public file set or committed file contents. The email-shaped match in a test is a synthetic `example.com` URL credential fixture.
- The existing remote history contains one initial commit with the license and ignore rules. Earlier prototype verification logs and history are not part of this repository.
- Existing Git author attribution is preserved by the repository owner's choice. Author email is intentionally not removed from commit metadata.
- Raw logs, result bundles, local evidence, and credential files are ignored. Prototype-specific workflow tools have been moved out of the public file set.
- The documentation now matches the repository's Apache 2.0 license and `Maybe` checkout name.

Repeat the secret checks with:

```sh
gitleaks git . --log-opts='--all' --redact
gitleaks dir . --redact
```

Keep any scanner reports under ignored `work/`; never publish raw findings containing a credential. Rotate a real leaked credential before considering history cleanup.

## Build and demo verification

- All 53 Swift tests passed from this checkout.
- All seven simulator UI cases have passing results: six in the full suite, plus a successful targeted source-editor rerun after adjusting an XCTest tap that retried after dismissal.
- Fresh screenshots cover light/dark appearance, source editing, replay, accessibility text sizes, and the empty JEV settings sheet. Screenshot EXIF/text/timestamp metadata was stripped without changing pixels.
- The live recording also replayed through the CLI with exactly equal exported JSON.
- One real JEV Inbox request succeeded with synthetic input, returning 23% urgent / 77% not urgent. The app replayed the result without another model call. Key entry was not recorded. The demo guide describes video edits and distinguishes the live clip from the offline screenshot walkthrough.
- No remote push or history rewrite is part of this cleanup.
