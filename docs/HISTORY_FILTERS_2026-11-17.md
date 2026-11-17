# History filters: local Build 23 follow-up

Baseline: PR #32 commit `665faf9d`. No App Store submission, merge, app installation,
launch, preference change, schema migration, or Direct Paste behavior change.

## Scope

- History retains All, Text, Images and Pinned and adds Links. Text continues to
  include standalone links; Links narrows to text-only clips whose entire trimmed
  content is an HTTP(S) URL with a host. Prose with embedded URLs is still Text.
  Rich/mixed image-and-text clips remain Images, preserving Build 23 classification.
- Search terms, content choice and date range intersect. Date filtering happens
  before pagination; link classification uses full text, not truncated previews.
- Today/Yesterday follow local calendar boundaries. Past week includes today and
  the prior six calendar days; Past month includes today and the prior 29 days.
- Custom From/Through includes both selected dates. Reversed endpoints are treated
  as the same inclusive range. Calendar arithmetic respects daylight-saving days.
- Clear filters resets only History search/type/date, leaving Library search alone.
- Tab switches retain filters and surviving selection. Fresh panel opens retain
  Build 23's reset-to-History/clear-search behavior, including resetting dates.
- Templates retains the existing prompt-template behavior. No image categories,
  collections, most-used sort, or new persistence behavior are added there.

## Automated verification

- Synthetic offline development suite: 251 tests passed (185 platform, 66 core).
- Date/preset control keyboard focus now keeps native arrow/Return handling rather
  than triggering History navigation or paste; synthetic responder tests cover this.
- Added tests cover URL classification, sparse link results across scan pages,
  date/search/type intersection, pagination, mixed image/text, DST boundaries,
  reversed custom dates, empty results, and independent Library/tab state.
- Publishable-source hygiene and `git diff --check`: passed.
- Unsigned TestFlight configuration compiled and passed static package verification.
- Production copy-only regression: 3 tests passed. TestFlight import policy: 2 tests passed.

## Remaining validation

No live UI or real clipboard/Direct Paste testing was run. Narrow-window layout,
custom-date interaction, keyboard traversal, and VoiceOver need controlled UI QA.
The unsigned build is a compilation artifact, not an installable TestFlight release.

## User-approved Templates naming

The former Library is now labeled Templates throughout its tab, search, actions,
editor, empty states, accessibility labels and errors. This is a presentation-only
rename: internal section raw value, Library directory, library.sqlite, prompts
schema, entry IDs, template content, variables and defaults remain unchanged.

## Owner preview acceptance

Francisco reported all filter/Templates sample-preview tests passed and quit CS Test.
This covers the exercised sample UI, not actual clipboard capture, Direct Paste
or real-container migration. Reported November17,2026.
