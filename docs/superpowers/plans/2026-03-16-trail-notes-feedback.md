# Trail Notes Feedback Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add in-app feedback ("Leave a Trail Note") that creates GitHub issues via Cloudflare Worker.

**Architecture:** iOS `FeedbackView` → `FeedbackService` → `POST /api/feedback` on existing `pilgrim-worker` → GitHub Issues API. Rate limited by device token, labeled by category.

**Tech Stack:** SwiftUI (iOS), TypeScript/Cloudflare Workers (backend), GitHub REST API

**Spec:** `docs/superpowers/specs/2026-03-16-trail-notes-feedback-design.md`

---

## File Structure

| File | Repo | Action | Responsibility |
|------|------|--------|----------------|
| `src/handlers/feedback.ts` | pilgrim-worker | Create | Validate payload, rate limit, create GitHub issue |
| `src/types.ts` | pilgrim-worker | Modify | Add `GITHUB_TOKEN` to `Env`, add `FeedbackPayload` |
| `src/index.ts` | pilgrim-worker | Modify | Add `POST /api/feedback` route |
| `Pilgrim/Models/Feedback/FeedbackService.swift` | pilgrim-ios | Create | Network call to `/api/feedback` |
| `Pilgrim/Scenes/Settings/FeedbackView.swift` | pilgrim-ios | Create | Category cards, text editor, device info toggle, confirmation |
| `Pilgrim/Scenes/Settings/SettingsView.swift` | pilgrim-ios | Modify | Add Trail Note row |

---

## Chunk 1: Cloudflare Worker

### Task 1: Add feedback handler to pilgrim-worker

**Files:**
- Modify: `/Users/rubberduck/GitHub/momentmaker/pilgrim-worker/src/types.ts`
- Create: `/Users/rubberduck/GitHub/momentmaker/pilgrim-worker/src/handlers/feedback.ts`
- Modify: `/Users/rubberduck/GitHub/momentmaker/pilgrim-worker/src/index.ts`

- [ ] **Step 1: Add types**

Add to `src/types.ts` — append `GITHUB_TOKEN` to `Env` and add `FeedbackPayload`:

```typescript
// In Env interface, add:
  GITHUB_TOKEN: string;

// New interface:
export interface FeedbackPayload {
  category: "bug" | "feature" | "feedback";
  message: string;
  deviceInfo?: string;
}
```

- [ ] **Step 2: Create feedback handler**

Create `src/handlers/feedback.ts`:

```typescript
import { Env, FeedbackPayload } from "../types";

const MAX_FEEDBACK_PER_DAY = 5;
const MAX_MESSAGE_LENGTH = 2000;

const LABEL_MAP: Record<FeedbackPayload["category"], string> = {
  bug: "bug",
  feature: "enhancement",
  feedback: "feedback",
};

export async function handleFeedback(
  request: Request,
  env: Env,
): Promise<Response> {
  const deviceToken = request.headers.get("X-Device-Token");
  if (!deviceToken) {
    return jsonError("Missing X-Device-Token header", 401);
  }

  const tokenHash = await hashToken(deviceToken);

  let payload: FeedbackPayload;
  try {
    payload = (await request.json()) as FeedbackPayload;
  } catch {
    return jsonError("Invalid JSON payload", 400);
  }

  const validation = validatePayload(payload);
  if (validation) {
    return jsonError(validation, 400);
  }

  if (await checkAndIncrementRateLimit(tokenHash, env)) {
    return jsonError("Rate limit exceeded. Max 5 submissions per day.", 429);
  }

  try {
    await createGitHubIssue(payload, env);
  } catch (err) {
    console.error("GitHub API error:", err);
    return jsonError("Failed to submit feedback", 500);
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 201,
    headers: { "Content-Type": "application/json" },
  });
}

function validatePayload(payload: FeedbackPayload): string | null {
  if (!["bug", "feature", "feedback"].includes(payload.category)) {
    return "Invalid category";
  }
  if (!payload.message || payload.message.trim().length === 0) {
    return "Message is required";
  }
  if (payload.message.length > MAX_MESSAGE_LENGTH) {
    return `Message exceeds ${MAX_MESSAGE_LENGTH} characters`;
  }
  return null;
}

async function createGitHubIssue(
  payload: FeedbackPayload,
  env: Env,
): Promise<void> {
  const firstLine = payload.message.split("\n")[0].trim();
  const title =
    firstLine.length > 80 ? firstLine.slice(0, 77) + "..." : firstLine;
  const label = LABEL_MAP[payload.category];

  let body = payload.message;
  body += "\n\n---\n*Submitted via Trail Notes*";
  if (payload.deviceInfo) {
    body += `\n${payload.deviceInfo}`;
  }

  const response = await fetch(
    "https://api.github.com/repos/walktalkmeditate/pilgrim-ios/issues",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.GITHUB_TOKEN}`,
        Accept: "application/vnd.github+json",
        "User-Agent": "pilgrim-worker",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ title, body, labels: [label] }),
    },
  );

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`GitHub API ${response.status}: ${text}`);
  }
}

async function hashToken(token: string): Promise<string> {
  const data = new TextEncoder().encode(token);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function checkAndIncrementRateLimit(
  tokenHash: string,
  env: Env,
): Promise<boolean> {
  const key = `feedback:${tokenHash}`;
  const count = parseInt((await env.RATE_LIMIT.get(key)) ?? "0", 10);
  if (count >= MAX_FEEDBACK_PER_DAY) return true;
  await env.RATE_LIMIT.put(key, String(count + 1), { expirationTtl: 86400 });
  return false;
}

function jsonError(message: string, status: number): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
```

- [ ] **Step 3: Add route to index.ts**

In `src/index.ts`, add import and route. After the existing `/api/share` block (line 20), add:

```typescript
import { handleFeedback } from "./handlers/feedback";

// Add after the /api/share block:
    if (request.method === "POST" && url.pathname === "/api/feedback") {
      const response = await handleFeedback(request, env);
      console.log(`POST /api/feedback → ${response.status} (${Date.now() - start}ms)`);
      return response;
    }
```

- [ ] **Step 4: Test locally**

Run:
```bash
cd /Users/rubberduck/GitHub/momentmaker/pilgrim-worker
npx wrangler dev
```

Then test with curl:
```bash
curl -X POST http://localhost:8787/api/feedback \
  -H "Content-Type: application/json" \
  -H "X-Device-Token: test-token-123" \
  -d '{"category":"feedback","message":"Test trail note from dev","deviceInfo":"iOS 19.0 · iPhone 17 Pro · v1.2.0"}'
```

Expected: `201` with `{"ok":true}` and a new issue on the GitHub repo.

- [ ] **Step 5: Deploy**

Run:
```bash
cd /Users/rubberduck/GitHub/momentmaker/pilgrim-worker
npx wrangler deploy
```

- [ ] **Step 6: Commit**

```bash
cd /Users/rubberduck/GitHub/momentmaker/pilgrim-worker
git add src/types.ts src/handlers/feedback.ts src/index.ts
git commit -m "feat: add POST /api/feedback route for Trail Notes"
```

---

## Chunk 2: iOS FeedbackService

### Task 2: FeedbackService

**Files:**
- Create: `Pilgrim/Models/Feedback/FeedbackService.swift`

- [ ] **Step 1: Create FeedbackService**

Create `Pilgrim/Models/Feedback/FeedbackService.swift`:

```swift
import Foundation
import UIKit

enum FeedbackService {

    private static let baseURL = "https://walk.pilgrimapp.org"

    enum FeedbackError: LocalizedError {
        case networkError(String)
        case rateLimited
        case serverError(Int)

        var errorDescription: String? {
            switch self {
            case .networkError(let msg): return msg
            case .rateLimited: return "Too many submissions today."
            case .serverError(let code): return "Server error (\(code))"
            }
        }
    }

    static func submit(
        category: String,
        message: String,
        includeDeviceInfo: Bool
    ) async throws {
        let url = URL(string: "\(baseURL)/api/feedback")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(ShareService.deviceTokenForFeedback(), forHTTPHeaderField: "X-Device-Token")
        request.timeoutInterval = 15

        var body: [String: String] = [
            "category": category,
            "message": message
        ]
        if includeDeviceInfo {
            body["deviceInfo"] = deviceInfoString()
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw FeedbackError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw FeedbackError.networkError("Invalid response")
        }

        if http.statusCode == 429 {
            throw FeedbackError.rateLimited
        }

        guard (200...299).contains(http.statusCode) else {
            throw FeedbackError.serverError(http.statusCode)
        }
    }

    private static func deviceInfoString() -> String {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let device = UIDevice.current.model
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "iOS \(osVersion) · \(device) · v\(appVersion)"
    }
}
```

- [ ] **Step 2: Expose device token from ShareService**

Add a static method to `ShareService` so `FeedbackService` can reuse the same device token. In `Pilgrim/Models/Share/ShareService.swift`, add after the `deviceToken()` method:

```swift
    static func deviceTokenForFeedback() -> String {
        deviceToken()
    }
```

This changes `deviceToken()` visibility — since it's already `private`, we add a new internal method that calls it.

- [ ] **Step 3: Add file to Xcode project, build**

Add `FeedbackService.swift` to the Pilgrim target in `project.pbxproj`.

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Models/Feedback/FeedbackService.swift Pilgrim/Models/Share/ShareService.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat: add FeedbackService for Trail Notes submissions"
```

---

## Chunk 3: iOS FeedbackView + SettingsView

### Task 3: FeedbackView and SettingsView row

**Files:**
- Create: `Pilgrim/Scenes/Settings/FeedbackView.swift`
- Modify: `Pilgrim/Scenes/Settings/SettingsView.swift`

- [ ] **Step 1: Create FeedbackView**

Create `Pilgrim/Scenes/Settings/FeedbackView.swift`:

```swift
import SwiftUI

struct FeedbackView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: FeedbackCategory?
    @State private var message = ""
    @State private var includeDeviceInfo = true
    @State private var isSubmitting = false
    @State private var showConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if showConfirmation {
                confirmationOverlay
            } else {
                formContent
            }
        }
        .background(Color.parchment)
        .navigationTitle("Trail Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Leave a Trail Note")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
            }
        }
    }

    // MARK: - Form

    private var formContent: some View {
        ScrollView {
            VStack(spacing: Constants.UI.Padding.big) {
                categoryCards
                textEditor
                deviceInfoToggle
                if let errorMessage {
                    Text(errorMessage)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.rust)
                }
                sendButton
            }
            .padding(Constants.UI.Padding.big)
        }
    }

    private var categoryCards: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            ForEach(FeedbackCategory.allCases) { category in
                Button {
                    selectedCategory = category
                } label: {
                    HStack(spacing: Constants.UI.Padding.normal) {
                        Image(systemName: category.icon)
                            .font(.title3)
                            .foregroundColor(.stone)
                            .frame(width: 28)
                        Text(category.title)
                            .font(Constants.Typography.body)
                            .foregroundColor(.ink)
                        Spacer()
                        if selectedCategory == category {
                            Image(systemName: "checkmark")
                                .foregroundColor(.moss)
                                .font(Constants.Typography.caption)
                        }
                    }
                    .padding(Constants.UI.Padding.normal)
                    .background(
                        selectedCategory == category
                            ? Color.stone.opacity(0.08)
                            : Color.parchmentSecondary
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.normal)
                            .stroke(
                                selectedCategory == category ? Color.stone : Color.clear,
                                lineWidth: 1
                            )
                    )
                    .cornerRadius(Constants.UI.CornerRadius.normal)
                }
            }
        }
    }

    private var textEditor: some View {
        TextEditor(text: $message)
            .font(Constants.Typography.body)
            .foregroundColor(.ink)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 120)
            .padding(Constants.UI.Padding.small)
            .background(Color.parchmentSecondary)
            .cornerRadius(Constants.UI.CornerRadius.normal)
            .overlay(alignment: .topLeading) {
                if message.isEmpty {
                    Text("What's on your mind?")
                        .font(Constants.Typography.body)
                        .foregroundColor(.fog.opacity(0.5))
                        .padding(Constants.UI.Padding.small)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
            }
    }

    private var deviceInfoToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $includeDeviceInfo) {
                Text("Include device info")
                    .font(Constants.Typography.body)
            }
            .tint(.stone)
            if includeDeviceInfo {
                Text(deviceInfoPreview)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
        }
    }

    private var deviceInfoPreview: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        return "iOS \(UIDevice.current.systemVersion) · \(UIDevice.current.model) · v\(version)"
    }

    private var sendButton: some View {
        Button {
            submit()
        } label: {
            Group {
                if isSubmitting {
                    SwiftUI.ProgressView()
                        .tint(.parchment)
                } else {
                    Text("Send")
                        .font(Constants.Typography.button)
                }
            }
            .foregroundColor(.parchment)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(canSubmit ? Color.stone : Color.fog.opacity(0.2))
            .cornerRadius(Constants.UI.CornerRadius.normal)
        }
        .disabled(!canSubmit || isSubmitting)
    }

    private var canSubmit: Bool {
        selectedCategory != nil && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Submit

    private func submit() {
        guard let category = selectedCategory else { return }
        errorMessage = nil
        isSubmitting = true

        Task {
            do {
                try await FeedbackService.submit(
                    category: category.apiValue,
                    message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                    includeDeviceInfo: includeDeviceInfo
                )
                withAnimation(.easeInOut(duration: 0.5)) {
                    showConfirmation = true
                }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                dismiss()
            } catch {
                errorMessage = "Couldn't send — please try again"
                isSubmitting = false
            }
        }
    }

    // MARK: - Confirmation

    private var confirmationOverlay: some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            Spacer()
            Image(systemName: "checkmark")
                .font(.largeTitle)
                .foregroundColor(.moss)
            Text("Your note has been\nleft on the path.")
                .font(Constants.Typography.body)
                .foregroundColor(.ink)
                .multilineTextAlignment(.center)
            Text("Thank you.")
                .font(Constants.Typography.body.italic())
                .foregroundColor(.fog)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.parchment)
        .transition(.opacity)
    }
}

// MARK: - FeedbackCategory

enum FeedbackCategory: String, CaseIterable, Identifiable {
    case bug, feature, thought

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bug: return "Something's broken"
        case .feature: return "I wish it could..."
        case .thought: return "A thought"
        }
    }

    var icon: String {
        switch self {
        case .bug: return "ladybug"
        case .feature: return "sparkles"
        case .thought: return "leaf"
        }
    }

    var apiValue: String {
        switch self {
        case .bug: return "bug"
        case .feature: return "feature"
        case .thought: return "feedback"
        }
    }
}
```

- [ ] **Step 2: Add Trail Note row to SettingsView**

In `Pilgrim/Scenes/Settings/SettingsView.swift`, add a new section after the Audio section (before `.scrollContentBackground`):

```swift
                Section {
                    NavigationLink {
                        FeedbackView()
                    } label: {
                        Text("Leave a Trail Note")
                            .font(Constants.Typography.body)
                    }
                }
```

- [ ] **Step 3: Add files to Xcode project, build**

Add `FeedbackView.swift` to the Pilgrim target in `project.pbxproj`. Create the `Pilgrim/Models/Feedback/` directory if needed.

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Run all tests**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Scenes/Settings/FeedbackView.swift Pilgrim/Scenes/Settings/SettingsView.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat: add Trail Notes feedback view with pilgrim-themed categories and confirmation"
```
