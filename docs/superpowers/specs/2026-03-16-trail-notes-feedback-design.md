# Trail Notes — In-App Feedback

## Summary

Add an in-app feedback feature ("Leave a Trail Note") that lets users submit bugs, feature requests, and general feedback. Submissions create GitHub issues on `walktalkmeditate/pilgrim-ios` via a new route on the existing Cloudflare Worker.

## Motivation

- No in-app feedback path exists — users must email or find the GitHub repo
- Friction kills feedback; a two-tap flow inside the app captures thoughts while they're fresh
- GitHub issues with proper labels keep feedback actionable for the developer

## Design

### SettingsView

New section between Audio and the footer:

```
├─────────────────────────────────────┤
│ Leave a Trail Note               ›  │
└─────────────────────────────────────┘
```

NavigationLink to `FeedbackView`.

### FeedbackView

Three category cards at the top, a text editor, device info toggle, and send button.

**Categories** (tappable cards, one selected at a time):
- "Something's broken" → GitHub label: `bug`
- "I wish it could..." → GitHub label: `enhancement`
- "A thought" → GitHub label: `feedback`

Cards use `parchmentSecondary` background, `stone` border when selected. SF Symbols: `ladybug` / `sparkles` / `leaf`

**Text editor**: Placeholder "What's on your mind?". Minimum height ~120pt, grows with content.

**Device info toggle**: On by default. Shows the info that will be included: "iOS 19.0 · iPhone 16 Pro · v1.2.0". Styled in caption/fog below the toggle.

**Send button**: Stone background, disabled until category selected + text is non-empty. Shows a spinner while submitting.

**Error state**: If the request fails, show an inline message below the button: "Couldn't send — please try again" in rust color. No alert.

### Confirmation Overlay

After successful submission, the form is replaced with a centered confirmation:

```
          ✓

  Your note has been
  left on the path.

      Thank you.
```

- Checkmark in moss, text in ink/fog
- Fades in with `easeInOut(duration: 0.5)`
- Auto-pops back to Settings after 2.5 seconds via `dismiss()`

### Worker: `POST /api/feedback`

New route on the existing `pilgrim-worker` at `walk.pilgrimapp.org`.

**Request**:
```json
{
  "category": "bug" | "feature" | "feedback",
  "message": "The bell doesn't play when I start a walk",
  "deviceInfo": "iOS 19.0 · iPhone 16 Pro · v1.2.0"
}
```

**Headers**: `X-Device-Token` (same device token used for walk sharing, for rate limiting).

**Rate limit**: 5 submissions per device per day. Returns `429` if exceeded.

**Worker logic**:
1. Validate payload (category is one of three values, message is non-empty and ≤ 2000 chars)
2. Check rate limit via KV store (reuse existing `RATE_LIMIT` KV namespace with `feedback:` prefix)
3. Create GitHub issue via `POST https://api.github.com/repos/walktalkmeditate/pilgrim-ios/issues`
4. Return `201` on success, `429` on rate limit, `400` on validation error, `500` on GitHub API failure

**GitHub issue format**:
- **Title**: First line of message, truncated at 80 chars
- **Labels**: `["bug"]`, `["enhancement"]`, or `["feedback"]` based on category
- **Body**:
```markdown
{full message text}

---
*Submitted via Trail Notes*
{deviceInfo if provided}
```

**Worker secret**: `GITHUB_TOKEN` — fine-grained PAT with Issues read/write on `pilgrim-ios` only. Set via `wrangler secret put GITHUB_TOKEN`.

### iOS Networking

New `FeedbackService` struct (similar pattern to existing `ShareService`):
- `static func submit(category:message:deviceInfo:)` → async throws
- Posts to `https://walk.pilgrimapp.org/api/feedback`
- Includes `X-Device-Token` header (reuse existing device token from `ShareService` or `UserPreferences`)
- Maps HTTP status codes to typed errors (rateLimited, validationError, serverError)

## Files

| File | Repo | Action |
|------|------|--------|
| `Pilgrim/Scenes/Settings/FeedbackView.swift` | pilgrim-ios | Create |
| `Pilgrim/Models/Feedback/FeedbackService.swift` | pilgrim-ios | Create |
| `Pilgrim/Scenes/Settings/SettingsView.swift` | pilgrim-ios | Modify — add Trail Note row |
| `src/handlers/feedback.ts` | pilgrim-worker | Create |
| `src/index.ts` | pilgrim-worker | Modify — add route |

## Out of Scope

- Screenshot attachment
- Email collection
- User accounts
- Conversation/reply threading
- Offline queuing (if no network, show error, user retries later)
