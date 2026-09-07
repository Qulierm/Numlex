# Numlex Website Brief — Handoff for Implementation Agents

Dated fact snapshot: **2026-09-07** (repo `Qulierm/Numlex` at `ccf19b3`, release **4.6.0**).
Source priority: app source code > README > this document. If they disagree, re-verify against source before publishing.

This brief is the single handoff for agents building the Numlex website. It tells you the
product, the goals, the approved aesthetic, the exact assets you may use, the claims you may
and may not make, and how the work is packaged. It does **not** build the site, choose a
domain, or deploy anything.

---

## 1. What Numlex is

Numlex is a free, open-source (MIT) **notebook calculator for macOS**: a notepad where plain
lines — `30 + 567 × 2`, `15% of 4572`, `250 km to m`, `$500 to EUR`, `June 12 + 45 days` —
are evaluated live, strictly, with checked results in a side column. It is a native
Swift 6.2 + SwiftUI/TextKit app (not a web app), macOS 26+, Apple Silicon (arm64),
distributed as a plain DMG from GitHub Releases.

Positioning: a free, local-first, plain-text alternative to closed notepad calculators
(Soulver, Numi). Say "alternative to" — never claim feature parity, and never use
competitor artwork or trademarks.

Audience: students, developers, freelancers, budget/planning users who want math that
reads like notes.

## 2. Verified product facts (snapshot 2026-09-07)

| Fact | Value | Source |
|---|---|---|
| Latest release | 4.6.0 (stable, not prerelease/draft) | GitHub `releases/latest` |
| Platform | macOS 26+, Apple Silicon arm64 | `Info.plist` (`LSMinimumSystemVersion` 26.0), Mach-O arm64 |
| Signing | ad-hoc signed, **not notarized**, no App Store | release assets, README |
| License | MIT, Nikita Gostevsky © 2026 | `LICENSE` |
| Currency conversions | 166 ISO 4217 fiat codes (no crypto/precious metals), live free rates from open.er-api.com (no API key) | `FiatCurrencies.swift`, `RatesService.swift` |
| Unit conversions | 232 base unit definitions (length, mass, time, temperature, energy, data, finance, viscosity, …) plus SI-prefixed variants; mixed-unit expressions | `UnitCatalogData.swift` |
| Weather | `weather in <city>` via Open-Meteo (no key); only the explicit place you type is sent; **no GPS/location** | `WeatherService.swift` |
| Offline behavior | all calculations work offline; FX/weather use cached values until a fresh lookup is possible | services |
| Data | local persistence in Application Support; import/export sheets as `.nlx` files | README, `Localization.swift` |
| Constants | up to 100 app-wide constants, available in every sheet; **never embedded into `.nlx` exports** | `ConstantResolver.swift` |
| Linked answers | stable reference bubbles/tokens reuse earlier results live; source changes propagate; no cycles | engine |
| Sections/totals | `# Section` headings, a `total` line resets and totals its section; Total footer can be hidden | engine |
| Settings | 5 native tabs (General, Editing, Numbers, Constants, Styling) with native switches; Light/Dark | `SettingsView.swift` |
| Number formats | 4 presets (System, North America `en_US`, Western Europe `de_DE`, Eastern Europe `ru_RU`) + 3 toggles (convert-foreign-on-paste, thousands separator, compact notation); decimal-comma modes use `;` as list separator | `RegionalNumberFormat.swift` |
| Sheets/folders | named sheets; one-level folder tabs (built-in General + custom folders) in the sidebar | app |

### Claims you must NOT make
- No AI, no Foundation Models/on-device ML, no cloud sync, no collaboration, no web
  calculator, no mobile apps, no App Store distribution, no notarization, no "Intel Mac"
  support (arm64 only).
- No invented social links, e-mail addresses, domains, testimonials, download counts,
  user quotes, pricing comparisons, or benchmarks.
- Do not guarantee that right-click → Open *always* bypasses Gatekeeper on every macOS
  version; give honest, version-dependent guidance (below). Never recommend disabling
  Gatekeeper system-wide.
- The homebrew cask currently **lags** the latest release (see §8) — do not advertise
  automatic latest-version parity.

## 3. Goals / scope

**In scope:** one polished static landing page (optional separate privacy page) that
makes a macOS user trust the product and download it.

**Non-goals:** no runtime backend, no React/Electron app embed, no CMS, no analytics or
cookie consent by default, no fake contact-form backend, no automatic download on page
load (all downloads are user-triggered), no App Store-style marketing bloat.

### Suggested hero copy (proposals — label as such, owner may edit)
- Title: **Numlex — the notepad that does the math**
- Subtitle: *Type plain lines, get live, checked results. Natural math, variables,
  percentages, dates, unit and currency conversions, and reusable live answer tokens —
  local, free, and open source.*
- Primary CTA: **Download for macOS** → `https://github.com/Qulierm/Numlex/releases/latest`
  (keep this the primary stable CTA; pin tagged links only as secondary snapshots).
- Secondary: View on GitHub. Brew (with the lag note, §8).
- Tagline (existing brand line, verified in `Assets/DMG/numlex-tagline.png`):
  **"Think freely. We'll do the math."** — prefer rendering this as accessible HTML
  text, not as an image.

## 4. Page structure (ordered)

1. **Header** — wordmark + GitHub link (+ optional theme toggle, proposal only).
2. **Hero** — title/subtitle/CTAs, then **immediately below the primary download CTA**:
   the approved hero screenshot (user-supplied, §6.1), centered, linked to full size.
3. **Concise benefits** — 3–5 short benefit-oriented lines (plain text, no images):
   live checked results; plain language, no formula syntax; local-first & private.
4. **Feature demos — the four supplied GIFs**, 2-column grid on desktop, 1-column on
   mobile (never a horizontally scrolling table). Card titles/captions must match what
   the footage actually shows:
   - `base.gif` → "Variables & Functions" — variable assignments, percentage of a
     variable, power, trig, live Total.
   - `household.gif` → "Natural Calculations" — arithmetic, percentages, a section
     `total`, and a date calculation in a `# Household` section.
   - `kilometres.gif` → "Units & Currencies" — `250 km to m`, `34 C to F`,
     `$500 to EUR`, `500 g to oz` (note: the very end of this clip briefly shows a macOS
     "Exporting video" system dialog — a recording artifact; keep as-is, do not crop).
   - `linked.gif` → "Linked Answers" — result bubbles reused in later lines, updating live.
5. **Broader capabilities (text only — do not invent imagery for features with no
   supplied media)**: sheets & folders; regional number formats; custom styling &
   constants; import/export `.nlx`.
6. **Local-first / privacy** — data stays in Application Support; the only network calls
   are background FX-rate refreshes and Open-Meteo weather for the exact city you type;
   no account, no GPS, no sync.
7. **Download & install** — requirements (macOS 26+, Apple Silicon), DMG instructions,
   honest Gatekeeper note, SHA-256 verification snippet, Homebrew note (§8).
8. **FAQ** (proposals): Why no Intel build? (arm64 only.) Is it free? (Free, MIT.)
   What goes online? (§6 privacy facts.) Can I move my sheets? (`.nlx` files.)
9. **Footer** — MIT license (link `LICENSE`), author Nikita Gostevsky © 2026, GitHub,
   Product Hunt, AlternativeTo links (exact URLs in §7).

SEO/social: `<title>` draft "Numlex — the notepad calculator for macOS", meta
description from the subtitle, Open Graph image = hero screenshot, accessible landmarks
and heading order. Title/description are drafts, not owner-approved.

## 5. Design direction (user-approved aesthetic)

- **Default theme: dark.** The user-approved promotional demos are all dark; a light
  toggle is an optional proposal, not a requirement.
- **Actual app colors** (reference, sampled from the app, not a web system): editor
  background `#1E1E1E`, results column `#262628`, result/link accent `#65BCF6` (brighter
  `#99CEFF`), variable green `#6CDA76`, unit purple `#BE89EC`. Distinguish "app colors"
  from any **proposed** web palette: a web palette may borrow these hues but must be a
  coherent web system (backgrounds, surfaces, text, focus) that meets WCAG AA contrast —
  do not ship raw `#1E1E1E` as the whole-page background without designing the scale.
- **Restrained glass** (translucency) is welcome for navigation and cards; no huge
  gradient shelves, no DMG-installer artwork, no fake macOS chrome/traffic lights.
- Typography/whitespace: generous, readable at 320–1440px; scale type fluidly; keep
  captions one to two lines.
- Do not faithfully replicate GitHub table borders/padding if a simpler web grid looks
  better — the GitHub table exists only because README HTML is constrained.

## 6. Media — asset manifest & usage rules

### 6.1 Approved assets (exact repo paths; portable raw URLs verified 2026-09-07)

| Asset | Repo path | Raw URL | Size / bytes | SHA-256 |
|---|---|---|---|---|
| Hero screenshot (user-approved) | `Assets/NumlexScreenshot.png` | `https://raw.githubusercontent.com/Qulierm/Numlex/main/Assets/NumlexScreenshot.png` | 1860×1452, 747,188 B | `cd550159022cd4fdd978dbbf747978bb9a593fb4332b12cc1341171f3e77aedb` |
| App icon (raw PNG — use this, never `.icns`/`Assets.car`) | `Assets/AppIconPreview.png` | `…/main/Assets/AppIconPreview.png` | 512×512, 498,113 B | `f2b66202656f9d04372010d251a54668d1a9d153648bb4940465c43e85902932` |
| Demo: variables/functions | `Assets/Demos/base.gif` | `…/main/Assets/Demos/base.gif` | 1232×720, 4,649,399 B | `7760dd3b2b25a4016e79b5f4d181c1fe7a1881d6dc2dbe6f751c9726f536a732` |
| Demo: natural calculations | `Assets/Demos/household.gif` | `…/main/Assets/Demos/household.gif` | 1232×720, 4,759,081 B | `aecab0c7b6d81276200527af97917220df65539e1f3857716c286c0d1ecc76f4` |
| Demo: units & currencies | `Assets/Demos/kilometres.gif` | `…/main/Assets/Demos/kilometres.gif` | 1232×720, 4,430,122 B | `f8a4619e6649d9851a1f9ddab969fc695d009f473ccfb0aa6d727fabbde76fe8` |
| Demo: linked answers | `Assets/Demos/linked.gif` | `…/main/Assets/Demos/linked.gif` | 1232×720, 4,475,806 B | `13002e0d368e850c9356ec336d2c0d8794f4ba56d0c93b65df9ec0294ed635dc` |
| Tagline artwork (typography reference only) | `Assets/DMG/numlex-tagline.png` | `…/main/Assets/DMG/numlex-tagline.png` | 506×122, "Think freely. We'll do the math." | `5a59049027953cce5f23071fd3495f289f2bb5ca332534d202a8267193f49cde` |

**Recommendation: copy these files into the website project (or build-time download)
and serve them from your own origin** — hotlinking `raw.githubusercontent.com` from a
public site is a performance/reliability anti-pattern. The raw URLs are for provenance
and verification, not for production `<img src>`.

### 6.2 Media handling rules
- **Preserve the originals byte-exact** (hashes above). Never recompress, crop,
  re-time, or recolor the supplied files.
- Derived web formats (webm/mp4 + poster frame) may be created **only inside the
  website project, under new paths**, and only after visual equality is verified
  (frame-by-frame spot checks, identical aspect ratio 1232×720 → 16:9.55, same loop
  duration ~11.8–13.5 s). If the pipeline cannot convert, you may serve the original
  GIFs — but then do not claim the media is "lightweight".
- Playback: `autoplay muted loop playsinline`, pause when off-screen, expose controls,
  honor `prefers-reduced-motion` (show poster, no autoplay), lazy-load non-hero media,
  reserve aspect-ratio boxes to avoid layout shift, and **do not load all four
  animations simultaneously by default** (above-the-fold pair at most).
- Titles/captions must match what is actually shown in each clip (§4.4).

### 6.3 Rejected / non-canonical assets — do not use as site visuals
- `Assets/DMG/NumlexDMGBackground.png` and `Assets/DMG/NumlexDMGBackground@2x.png`
  — installer artwork, **rejected** as website visual reference.
- `Assets/AppIcon.icns`, `AppIcon.icon`, `AppIcon.iconset`, `AppIcon.compiled`,
  `AppIcon.exported.iconset` — legacy/canonical icon *sources* for the macOS build, not
  website media; the site icon is `AppIconPreview.png` (512×512 raw PNG).
- `Examples/` — user-owned untracked code samples; not website assets.
- Known issue: the approved hero screenshot contains the section header typo
  **"Convertations"**. Do not fake-edit the screenshot; if the owner wants it clean,
  request a recapture.

## 7. External links (exact, verified)

- Product: `https://github.com/Qulierm/Numlex`
- Primary stable download CTA: `https://github.com/Qulierm/Numlex/releases/latest`
- Pinned 4.6.0 snapshot: `https://github.com/Qulierm/Numlex/releases/tag/4.6.0`
- Pinned DMG: `https://github.com/Qulierm/Numlex/releases/download/4.6.0/Numlex-4.6.0-macOS-arm64.dmg`
  (3,753,427 bytes; SHA-256 `d8b1dd0086220076d47df3b12cab5fd42afefff3d7a19a269fe17feeb3d1e168`)
- Checksums: `https://github.com/Qulierm/Numlex/releases/download/4.6.0/SHA256SUMS`
- License: `https://github.com/Qulierm/Numlex/blob/main/LICENSE` (raw: `…/raw/main/LICENSE`)
- README (content source): `https://raw.githubusercontent.com/Qulierm/Numlex/main/README.md`
- Homebrew tap: `https://github.com/Qulierm/homebrew-tap`
- Product Hunt: `https://www.producthunt.com/products/numlex`
- AlternativeTo: `https://alternativeto.net/software/numlex/about/`
- Provider docs (if cited): Open-Meteo `https://open-meteo.com/`, open.er-api.com `https://open.er-api.com/v6/latest/EUR`

## 8. Download, install & Gatekeeper content requirements

State exactly:
- Requirements: **macOS 26 or later, Apple Silicon (arm64)**. No Intel build exists.
- Steps: download the DMG from the latest release, open it (a plain, unstyled DMG),
  drag **Numlex.app** to Applications.
- Gatekeeper (honest, version-dependent): the app is ad-hoc signed and not notarized.
  On first launch, if macOS blocks it, Control-click (right-click) **Numlex.app** →
  **Open** → confirm. Whether this works depends on the user's macOS version and
  system state — say so; link Apple's official guidance on opening apps (verify the
  URL before publishing); never tell users to disable Gatekeeper globally.
- Verification (optional, show as copyable terminal block):
  `shasum -a 256 -c SHA256SUMS` from the release assets.
- Homebrew (secondary, with honest note): `brew install --cask Qulierm/tap/numlex` —
  custom tap (`Qulierm/homebrew-tap`); **the cask currently pins 4.5.1 while the latest
  release is 4.6.0**, so note that the tap can lag and link
  `https://github.com/Qulierm/homebrew-tap`.
- Release-link hygiene: primary CTA must stay `/releases/latest` (stable across
  versions). The pinned 4.6.0 links are a **tagged snapshot** for this release; keep a
  maintenance note in the site source ("update pinned links on each release; never
  hardcode a version-specific filename under `/latest/download/`"). Fetching release
  metadata at build time is optional (respect rate limits, cache, fall back to the
  static snapshot); never ship an API token to the client.

## 9. Stack & hosting (open decisions — proposals, not user-approved)

- **Static-first**: Astro or any equivalent static export. No required runtime backend.
- Site code lives in a **separate directory or repository** to be agreed with the owner;
  do not move Swift sources or app assets out of the app repo (copy assets in).
- Domain, canonical URL, and OG image URLs are **environment-configured placeholders
  until the owner picks a domain — placeholders must not ship**.
- No analytics/cookies by default; no contact form without a real backend (link to
  GitHub issues instead — support happens there).
- No automatic install/download on page load; every download is a user click.

## 10. Work packets (for the respective agents)

1. **Design** — dark-first design system (surfaces/type/spacing/focus states) inspired
   by §5; desktop + mobile layouts for §4; deliverable: annotated mockups or design tokens.
2. **Frontend** — implement the landing page (static export), responsive §4 structure,
   media behavior per §6.2, SEO/OG per §4, placeholders per §9. Deliverable: buildable
   static site + preview.
3. **Content** — finalize copy from the labelled proposals in §3/§4/§8 (owner review),
   FAQ, privacy page if adopted. No claims outside §2.
4. **Media** — optional GIF→webm/mp4 + poster conversion with the equality checks of
   §6.2; hero/icon optimization that preserves bytes or documents lossless re-encode.
5. **QA** — run the acceptance checklist (§11) and collect evidence.
6. **Deploy** — owner-chosen static host; verify live page; keep `/releases/latest` CTA
   and pinned-snapshot note intact. No release/tag/tap/app mutation from this work.

## 11. Acceptance checklist (QA evidence required)

- Layout at **320 / 390 / 768 / 1440** px: no horizontal scroll, 2-col demo grid
  collapses to 1-column on mobile, hero fits, captions wrap, no clipped media.
- Keyboard focus order visible throughout; screen-reader landmarks/headings; **WCAG AA**
  contrast on all text; `prefers-reduced-motion` shows posters instead of autoplay.
- Media: the four approved demos present, correctly captioned, actually animating (or
  reduced-motion poster), no 4-way simultaneous autoplay.
- Links: every URL in §7 live and correct; download CTA reaches the latest release;
  pinned 4.6.0 links resolve; brew command text matches §8.
- Facts: nothing outside §2; brew lag note present; "not notarized / arm64 / macOS 26+"
  stated accurately; no prohibited claims from §2.
- Performance (proposed budgets — targets, not current achievements): Lighthouse
  Performance ≥ 90 and LCP < 2.5 s on the landing page after media optimization;
  total media transfer budget to be set by the media packet.
- Static/SEO: semantic HTML, meta title/description, OG tags, license attribution in
  footer, privacy wording matches actual behavior (§4.6).

## 12. Open questions for the owner (non-blocking for a static draft)

1. Domain & hosting (site stays environment-configured until answered).
2. Stack: Astro or equivalent — confirm.
3. Languages: English default is proposed; additional languages (e.g., Russian) later?
4. Release sync: manual pinned-link updates per release, or build-time fetch?
5. Analytics: confirm none, or specify a privacy-respecting tool.

## 13. Do not invent / final handoff expectations

Do not invent: features beyond §2, social accounts, e-mail, domains, testimonials,
download numbers, pricing or benchmark claims, Intel/mobile/web/AI capabilities,
notarization or App Store status.

Final handoff from the implementation agents must include: the live URL, screenshots at
320/390/768/1440, Lighthouse output (labelled as measurements of the deployed build),
a link audit result, and the media conversion report (or "originals served as-is") —
so the owner can verify against this brief before launch.
