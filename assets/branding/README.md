# NexaPOS launcher artwork

`nexapos-launcher.svg` is original geometric artwork created for this repository.
It follows the existing `BrandMark` POS-terminal concept and `AppBrand` blue
(`#2563eb`) and teal (`#0d9488`) palette. No third-party logo, Material icon
glyph, font outline or user-provided image was copied.

The generated Android PNGs preserve the existing 48/72/96/144/192-pixel density
sizes. The Windows ICO contains explicit 16/24/32/48/64/128/256-pixel frames.
`PROVENANCE.json` records the source and output hashes. These launcher files are
native platform resources; they add no Dart dependency or runtime download.

To regenerate, use the optional asset tool with Pillow 12.3.0:

```sh
python3 tool/generate_launcher_icons.py
python3 tool/generate_launcher_icons.py --check
```

Pillow is needed only to maintain these assets. Existing Flutter builds consume
the checked-in PNG and ICO files directly.
