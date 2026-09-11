# Numlex documentation

This directory holds the **canonical, versioned source documents** for Numlex.
They describe the current `main` branch; published releases may lag behind.

## Read the documentation

The published, English, searchable documentation site is built from a separate
repository and is the best place to start:

- **Live docs:** <https://numlex.tech/docs/> — getting started, the full sheet
  language, catalogs and guides.

The website is an English adaptation; the documents below remain the source of
truth that the website is verified against.

## Canonical source documents

| Document | Language | Scope |
| --- | --- | --- |
| [SYNTAX_REFERENCE.md](SYNTAX_REFERENCE.md) | Russian | Every construct the engine accepts: line forms, numbers and bases, operators, all 23 built-in functions, percentages, money, `total`, dates, units and the full non-currency unit catalog, currencies, network queries, regional number formats, result display, answer tokens, constants and the keyword index. |
| [SETTINGS_AND_APPEARANCE.md](SETTINGS_AND_APPEARANCE.md) | English | The six Settings categories (icon-over-label tiles across the top) and every appearance/formatting contract: General (language, appearance, icon, notebook), Editing, Numbers, Constants & Units, Styling, About (app identity + updates) — including per-answer formatting, line highlights, the answer column, syntax colors and the line-number gutter. |
| [UPDATES.md](UPDATES.md) | English | Secure in-app updates: manual and automatic checks, the HTTPS feed and EdDSA archive signatures, privacy, the first-release bootstrap, signing requirements, key backup and the release-feed workflow. |

## `main` versus releases

Both documents track the current `main` branch. Released builds may lag behind
it: 4.8.2 is the current release; 4.8.0 was the first one with secure in-app
updates, so 4.8.0 and later update in-app while 4.7.0 and earlier must install
the current release manually once. When a guide mentions a
behaviour newer than the released build, it says so explicitly.

## Updating the documentation

1. Change behaviour or a contract in the Swift source, or add a test that pins it.
2. Update the matching document here in the same commit.
3. Update the published website pins (see `docs/SYNTAX_DOCUMENTATION.md` in the
   website repository) so the site cites the new revision.

Guidelines for both documents:

- Retypeable examples only, verified against the engine (no invented syntax).
- Syntax keywords stay English even in the Russian document.
- No claims about behaviour that the source and tests do not pin.
- Keep the document's own structure stable: headings are referenced by the
  website's source-coverage contract, one primary owner per content section.

## Related

- [README](../README.md) — install, build, architecture and license.
- [LICENSE](../LICENSE) — MIT.
