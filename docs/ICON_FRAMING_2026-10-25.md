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

## Revised scale candidate — owner review required

The owner did not approve candidate `7978cc4e`; its central artwork still had
too much internal spacing. A second built-in imagegen edit enlarges the arrow
and overlapping squares together, preserving the brand concept and palette.
Exact raster pixels changed. This new candidate requires fresh owner review;
the independent review of the earlier commit does not cover this revision.

Measured bright-foreground bounds on the normalized 1024px masters are
`(155, 176, 850, 831)` before and `(99, 120, 895, 874)` after: approximately
15% more width and height, from 68% to 78% of canvas width. The new mark retains
roughly 10–15% clearance to the canvas edges and is not clipped by the system
mask in the inspected previews.

The final revised icon SHA-256 is
`bb3bac3fd1d5e624cd7bda3c32415b3f5312ffbff1ed743b536afc3c2a75d58c`.
This supersedes the candidate hash and all-opaque validation above. Seven large
representations remain full-bleed opaque. For the three legacy 16/32px
representations (`icon_16x16`, `icon_16x16@2x`, `icon_32x32`), the system-rendered
256px candidate supplies its rounded mask, cropped to the 204px blue tile and
normally resized to 16/32px. This is packaging, not a further logo edit. It avoids
the unmasked square bitmap and legacy encoder corner artifact observed through
the system API at 32px. No hand-painted raster or new design was introduced.

Native system previews from fresh bundle paths were inspected at 256, 64 and
32px. The rounded blue tile remains full size, with a larger central logo and
no gray surround or logo clipping. All ten ICNS dimensions and expected alpha
ranges pass. Final unsigned Production compilation/static packaging verification,
source hygiene, native gates and diff whitespace checks pass. The review PNG
compares prior and revised candidates at all three sizes, with the raster-change
and owner-review caveats visible. Actual Dock runtime and store appearance remain
unrun, and the installed build 10 remains unchanged.
