# LinkedIn Safety Protocol

**Getting banned from LinkedIn would be catastrophic. These rules are non-negotiable.**

browsermcp controls the user's real Chrome browser with their real LinkedIn session. This means
browser fingerprinting is not a concern — but behavioral detection absolutely is. LinkedIn
monitors for automation through timing patterns, repetitive access, and unnatural browsing
behavior.

## Rules

### 1. WebFetch First
Always try `WebFetch` for job posting data before resorting to browsermcp. Job postings are
often semi-public and WebFetch avoids triggering any LinkedIn automation detection.

### 2. Page Load Limits
- **Per job**: Max 2-3 LinkedIn page loads (company page + people tab)
- **Per session/conversation**: Max 15 total LinkedIn page loads
- Track your count mentally. When you hit the limit, STOP.

### 3. Never View Individual Profiles
Do not navigate to any individual LinkedIn profile URL (linkedin.com/in/...) automatically.
The connection search should only use the company page's "People" section, which shows
connection summaries without triggering profile view notifications or tracking.

### 4. Mandatory Randomized Delays
After EVERY `browser_navigate` to any linkedin.com URL:
1. Call `browser_wait` with a **randomized** duration between 3000-8000ms
2. Never use round numbers (use 4200, 6700, 3100, 5800 — not 3000, 5000, 8000)
3. Never use the same delay twice in a row

### 5. Natural Scrolling Pattern
After the page loads and the wait completes, simulate natural reading:
1. `browser_press_key` with `PageDown` → `browser_wait` 1500-3000ms
2. `browser_press_key` with `PageDown` → `browser_wait` 2000-4000ms
3. Optionally scroll back up with `PageUp` → `browser_wait` 1000-2000ms
4. THEN take a `browser_snapshot` to read the content

### 6. Breather Pages
Between LinkedIn page loads, navigate to a non-LinkedIn URL:
- `browser_navigate` to `google.com` or the company's own website
- Wait 1000-2000ms
- Then navigate to the next LinkedIn page

This breaks up repetitive linkedin.com access patterns in the browser history.

### 7. No Write Actions — EVER
Never automate ANY of these on LinkedIn:
- Sending connection requests
- Sending messages or InMail
- Clicking "Easy Apply"
- Endorsing skills
- Liking, commenting, or sharing posts
- Following companies or people
- Any action that modifies LinkedIn state

These are ALWAYS done manually by the user.

### 8. CAPTCHA / Unusual Activity Detection
If a `browser_snapshot` or `browser_screenshot` reveals:
- A CAPTCHA challenge
- An "unusual activity detected" message
- A login/verification prompt
- Any security checkpoint

**Immediately:**
1. Stop ALL LinkedIn browsermcp operations for the rest of the session
2. Navigate to `google.com`
3. Alert the user with a clear warning
4. Do NOT attempt to solve or bypass the challenge

### 9. Session Hygiene
- At the start of any LinkedIn browsing, take a `browser_screenshot` first to verify
  the browser is in a normal state (logged in, no warnings)
- At the end of LinkedIn browsing, navigate to `google.com` to cleanly exit
- Never leave a LinkedIn page open in the background while doing other browsermcp work

### 10. Audit Trail
All browser navigations are logged to `/home/jack/workspace/job-search/linkedin-audit.log`
by a hook. This creates accountability. If the user asks how many LinkedIn pages were
accessed, check this log.

## Example Safe Connection Search Sequence

Use LinkedIn's conversational people search to find 1st+2nd degree connections in one page load:

```
URL pattern:
https://www.linkedin.com/search/results/people/?keywords=my%20connections%20to%20people%20who%20currently%20work%20at%20<COMPANY>&origin=FACETED_SEARCH&network=%5B%22S%22%2C%22F%22%5D

1. browser_screenshot                          # Verify browser state
2. browser_navigate → people search URL        # Page load #1 (1st + 2nd degree)
3. browser_wait(4700)                          # Randomized delay
4. browser_press_key(PageDown)                 # Natural scroll
5. browser_wait(2200)
6. browser_press_key(PageDown)
7. browser_wait(1800)
8. browser_snapshot                            # Read connections
9. browser_navigate → google.com              # Clean exit
```

Total LinkedIn page loads: 1. Total time: ~15 seconds of natural-looking browsing.
Past 2nd degree connections is useless — don't bother with 3rd+ degree searches.
