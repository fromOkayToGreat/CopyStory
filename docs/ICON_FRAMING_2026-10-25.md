# Icon framing correction

Prepared against main `5ee2d361c1ccbbc1782750d67802d67ec500a970`.

The supplied screenshot shows a gray rounded system tile around a smaller blue
CopyStory icon. The gray tile is absent from the decoded source artwork. The
installed TestFlight 1.0.0 (10) icon and the original repository resource have
the same SHA-256, `ece54cb1e50576c50c98543e63fc0e3b6a2b3643f6b735e42aa1989b909e4623`.
All ten source representations contain the blue rounded tile with transparent
padding; the 1024px alpha bounding box is `(71, 85, 952, 938)`.

Apple describes legacy icon masking and automatic scaling in
[Say hello to the new look of app icons](https://developer.apple.com/videos/play/wwdc2025/220/).
A read-only `NSWorkspace.icon(forFile:)` render of the installed bundle reproduces
the gray surround. This establishes system legacy framing, rather than baked-in
gray padding, as the cause on the inspected macOS 27 system.

## Minimal correction

The repository has no editable vector or icon-generation source. The built-in
imagegen edit extends the existing blue background to an opaque square canvas,
retaining the cyan history arrow, overlapping squares, palette and layout. It
does not introduce a new logo. Raster generation can introduce small pixel
differences; this is a visual brand-preserving correction, not a lossless edit.
The edit prompt requests preservation of all interior artwork and changes only
to the transparent margin and outer rounded tile boundary.

The generated 1254px square was normalized to 1024px, resized with Lanczos into
the same ten named macOS icon representations, and packaged with Apple iconutil.
The system supplies the rounded mask. No gray border, rounded transparent canvas
or second container is stored in the new source.

New `Resources/CopyStory.icns` SHA-256:
`5d6ade6524c91186139a14fed89d7685fc1a7d2724ef96de82e6babc0a12c61c`.
Only the icon, its two exact-hash validation pins, and this note change.
The earlier packaging review records the historical resource hash.

## Validation

- Native iconutil extraction yields all ten representations: 16, 32, 64, 128,
  256, 512 and 1024 raster pixels, including the required Retina duplicates.
- Every decoded source representation is fully opaque (alpha 255 throughout).
  Transparency belongs to the system-rendered outer mask, not source padding.
- Eight representations round-trip with exact RGBA pixels. Apple's legacy
  encoding changes the blue channel in one bottom-right pixel at 16px and four
  bottom-right pixels at 32px. These positions are outside the system rounded
  mask; no interior logo pixels change in packaging. A PNG-only packaging
  experiment was not adopted.
- Unsigned Production build and `verify-production.py` passed: correct icon
  metadata/hash and source-to-bundle equality, arm64/minimum OS 26.0, privacy
  manifest and production gates. Source hygiene, native gates, and diff
  whitespace checks passed. No runtime code changes require behavioral tests.
- The built bundle's read-only system icon render fills the normal rounded
  mask with blue, with no gray outer tile. This verifies local system rendering;
  App Store/TestFlight presentation and macOS 26 were not exercised.

No explicit signing step ran (the arm64 linker emits its normal unsealed ad hoc
signature). No app was installed or launched, no clipboard was read, and no
push, PR, merge or Apple upload occurred. The installed build 10 was read only.

A new distributed build is required; changing this source cannot update build
10. Release numbering, signing and distribution remain separate steps.
