# App Store Metadata — Server Health: SSH Monitor

**Source draft for v1.0 submission. Review, then I'll push to ASC via API.**

---

## App Information

- **Bundle ID:** `com.serverhealth.app`
- **App Store name:** Server Health: SSH Monitor (already set, 26 chars)
- **Primary category:** Developer Tools
- **Secondary category:** Utilities
- **Age rating:** 4+ (no objectionable content)
- **Copyright:** © 2026 Taha Ercan

---

## URLs

- **Support URL:** `https://github.com/tahaercan/serverhealth/issues`
- **Marketing URL:** `https://tahaercan.github.io/serverhealth/` (optional but recommended)
- **Privacy Policy URL:** `https://tahaercan.github.io/serverhealth/privacy/`

---

## Subtitle (max 30 chars)

> Monitor Linux servers via SSH

(29 chars)

---

## Promotional Text (max 170 chars, editable post-submission)

> Lightweight, privacy-first SSH monitor. Add your Linux servers, set thresholds, get local notifications. No third-party backend. Open source.

(140 chars)

---

## Keywords (max 100 chars, comma-separated, no spaces after commas)

> ssh,server,monitor,linux,vnstat,bandwidth,sysadmin,devops,uptime,cpu,ram,disk,vps,docker,hosting

(95 chars)

---

## Description (max 4000 chars)

> Server Health is a lightweight, privacy-first iOS monitor for your Linux servers — over SSH, directly from your phone. No agent on your servers. No third-party cloud. No telemetry.
>
> ADD A SERVER ONCE
> Add a server with a one-time SSH key handshake. Your password is used once to install a key, then forgotten. From that moment on, only the SSH key (held in your iPhone Keychain) is used. The first time we see your server's host key we pin it; if the key ever changes, the connection blocks — TOFU protection against MITM.
>
> PICK WHAT TO WATCH
> 22+ built-in checks: CPU load, memory and disk usage, root and per-path disk, load averages, uptime, zombie processes, active TCP connections, port open/closed, failed logins (today), service status (systemd), running and stopped Docker containers, pending security updates, reboot required, active SSH sessions, sudo usage (today), top CPU process, monthly and daily bandwidth (via vnstat, with consent install), and custom shell commands.
>
> Set a threshold per rule (above / below), pick a check interval, and write a custom notification message using {value} and {unit} placeholders.
>
> ALERTS ON YOUR DEVICE
> When a rule fires, Server Health sends a local notification. iOS shows banners when the app is in foreground; lock-screen notifications when it's not. Manual refresh is always one tap away.
>
> 24 HOURS OF HISTORY
> Every check is timestamped and charted. Tap a metric tile to see its 24-hour trend, rendered from on-device snapshots — no network call to draw the chart.
>
> HOME SCREEN WIDGET
> A small or medium widget shows your servers at a glance: green when everything's OK, red when a rule fires, orange when a server is unreachable. The widget never exposes hostnames or IPs — only your server's name.
>
> PRIVATE BY DESIGN
> · No analytics, crash reporting backend, advertising, or tracking.
> · The app connects only to the servers you add.
> · The SSH key is generated on your device and stays in the Keychain.
> · The activity log of every command run is kept on-device for 3 days, then auto-deleted.
> · Open source — read every line at github.com/tahaercan/serverhealth.
>
> 7 LANGUAGES
> English, Turkish, French, German, Spanish, Italian, Portuguese (Brazil).
>
> PRO UPGRADE — $19.99 / year
> Free tier: 1 server, 3 rules per server.
> Pro tier: unlimited servers, unlimited rules, every future Pro feature included with your subscription.
>
> HONEST ABOUT iOS BACKGROUND LIMITS
> Apple decides when to run background checks. The app schedules both BGAppRefresh and BGProcessing so iOS has more chances to fire. Settings shows you the actual number of automatic checks iOS has run. For guaranteed cadence, a server-side monitor is the right tool — Server Health is for the case where you want quick visibility on the device you already carry.

(~3,050 chars)

---

## What's New

Per Apple's API behavior, the `whatsNew` field cannot be edited on v1.0. Skip for initial submission; we set it for the first update.

---

## Age Rating questionnaire (planned answers)

All categories: **None / No**. Specifically:

- Cartoon or Fantasy Violence: None
- Realistic Violence: None
- Sexual Content or Nudity: None
- Profanity or Crude Humor: None
- Alcohol, Tobacco, or Drug Use or References: None
- Mature/Suggestive Themes: None
- Horror/Fear Themes: None
- Gambling: None
- Contests: No
- Unrestricted Web Access: No
- User Generated Content: No
- Medical/Treatment Information: No
- Has Frequent or Intense Themes: No
- Made for Kids: No
- Age Assurance: No

Result: 4+ ✓

---

## Localized variants (other 6 languages)

I'll auto-translate the subtitle / promotional text / keywords for tr, fr, de, es, it, pt-BR using consistent terminology. The full description will be translated unless you'd prefer to leave non-en locales using English (Apple shows en-US as fallback automatically).

Tell me if you want all 7 languages localized or just en-US + tr.

---

## Privacy nutrition labels (web UI only)

Set in ASC web → App Privacy → "Data Not Collected". Then publish. Standard for an open-source no-backend app.

---

## App Pricing tier (web UI only)

Set in ASC web → Pricing and Availability → Free tier. Then save.

---

## Subscription review screenshot

For the IAP submission, Apple wants a 1024×1024 screenshot of the paywall. I'll capture from the simulator and upload via API.

---

## Screenshots

I will capture from the simulator:

- **6.7" iPhone (iPhone 17 Pro Max, 1290×2796)**: 5–6 screenshots covering Dashboard, Detail, Add Server wizard, Add Rule, Widget config, Paywall.
- **iPad Pro 13" (2064×2752)**: 1 screenshot (Apple requires at least one for universal apps).

Upload via API after en-US locale is filled.
