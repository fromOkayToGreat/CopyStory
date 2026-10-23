# Publishable reconstruction snapshot

Source is reconstructed from pinned local commit
`e3699c1570272f5a45ec464ea6594626058bc131`, not exact installed build7 source.
This snapshot has remote main `2af4ff0535af84be570f81f14482971fb27d77b8` as
its direct parent. The raw pinned commit and preparation history stay preserved
locally and are not ancestors of this publishable branch.

Product/test/build source is retained from that pin. The local
`Reconstruction/INPUT_MANIFEST.json` and `QA/FocusIdentityCheck/` preparation
fixtures are omitted: they contained machine/evidence paths and are unnecessary
for the product target. Two historical documentation files have personal paths
removed. Saved local artifacts preserve the original evidence without publishing
it. No source was recovered by claiming the installed binary matches this tree.

Subsequent commits apply reviewed interface/Xcode/validation changes and ordinary
development integration. See `docs/DEVELOPMENT.md` for current behavior and limits.
