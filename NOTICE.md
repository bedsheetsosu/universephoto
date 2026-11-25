# Notices and third-party credits

UniverseStudio is licensed under the UniverseStudio License (USL) 1.0 (see LICENSE).
It uses **no external packages** — only Apple's macOS SDK system frameworks. The list
below is for attribution, not a dependency: none of this code is bundled as a library.

## Private CoreGraphics display API (CVirtualDisplay)

`Sources/CVirtualDisplay/CVirtualDisplay.{h,m}` declares Apple's **private** and
undocumented `CGVirtualDisplay` interface, used only for the optional "second screen"
mode. Apple ships these classes but publishes no header.

The declared interface surface follows the same private API that open-source projects
such as **DeskPad** make use of:

> DeskPad — https://github.com/Stengo/DeskPad — © Stengo, MIT License.

These are interface declarations of Apple's API (not DeskPad's own implementation),
re-declared here independently; DeskPad is credited as a reference for the API shape.
Its MIT license permits this use with attribution, which this notice provides.

## UniversePen

UniversePen is a separate project. Its SDK and API documentation are distributed under
the MIT License; see `UniversePen/SDK/LICENSE`. UniverseStudio only calls the
documented public UniversePen plugin API and bundles no UniversePen application source.
