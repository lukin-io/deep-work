# Application icon

The single production source is `DeepWork/Resources/Assets.xcassets/AppIcon.appiconset`. It contains the approved Icon 1.0 artwork in ten standard/Retina sizes, plus `Contents.json`. The 1024px master is `icon_512x512@2x.png`; no duplicate master or prebuilt ICNS belongs in the source tree.

```text
DeepWork/Resources/
├── Info.plist
└── Assets.xcassets/
    ├── Contents.json
    └── AppIcon.appiconset/
        ├── Contents.json
        └── icon_*.png
```

Xcode compiles the catalog through its Resources phase with `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon`. The Command Line Tools build uses Apple's `iconutil` to package the same existing PNGs into `Contents/Resources/AppIcon.icns`. It performs no resizing, cropping or recoloring. Intermediate iconsets and generated ICNS files stay in temporary/build output. `CFBundleIconFile` names the resulting bundle resource.

From the project root:

```sh
./DeepWorkTests/Icon/test-app-icon.sh
./scripts/build-app.sh
swift scripts/verify-app-icon.swift ".build/Deep Work.app" \
  DeepWork/Resources/Assets.xcassets/AppIcon.appiconset
```

Native ImageIO/AppKit validation checks all ten logical/pixel sizes, transparency, metadata, and every generated representation's pixels against the catalog. A differently encoded ICNS can preserve exactly the same artwork; container-byte equality is not required. Missing/corrupt resources and mismatched artwork must fail validation. No test or build reads an original delivery archive.

The build updates the app bundle timestamp after signing so macOS refreshes a cached icon. Regression use case: quit the previous build, rebuild, and reopen; About Deep Work and the Dock must show the blue ring. Updating only nested resource files previously left the generic icon cached. No global icon cache reset or application-code override is needed.

## Provenance and local originals

Before cleanup, every catalog file was checked byte-for-byte against the supplied ZIP. The standalone 1024px PNG is identical to the catalog's largest image. The original PNG, ICNS, and ZIP were moved unchanged to `.local-artifacts/icon-delivery-archive/`, which is ignored by Git and separate from build output. This local preservation archive is not required by the app, tests, Xcode, or a clean checkout. The ZIP retains the original delivery notes and unused Icon Composer interpretation; neither is a production resource.

Original SHA-256 values:

```text
f1750a6f9e837d6e37d95de1b7ce3afbd0c9efe70425c016ea0d8645413cbc8c  DeepWork-Icon-1.0-1024.png
74ffe03654e4b5fb317dc84e277ab895340fcf6c303bfd581812f26074f2b905  DeepWork-Icon-1.0.icns
e6b0fd2c8331dabc96f4921b94cafa69ffe5f305a199a193a7a942803895b3c3  deep-work-icon-1.0.zip
```

For a future approved icon, replace the production catalog's ten images and metadata, run the commands above, and inspect the rebuilt app. Keep editable design deliveries outside application resources. Do not add another production icon folder or depend on the local archive. Full Xcode compilation still requires installing and selecting Xcode; CLT checks do not establish an `actool` result.
