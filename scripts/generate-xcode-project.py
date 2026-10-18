#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project from the native source tree.

The app and native test bundle link the same local DeepWorkCore package used by
the command-line build. Run after adding/removing application or test sources.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "DeepWork.xcodeproj"
objects: dict[str, dict] = {}


def identifier(name: str) -> str:
    return hashlib.sha256(name.encode("utf-8")).hexdigest()[:24].upper()


def add(key: str, isa: str, **values) -> str:
    reference = identifier(key)
    objects[reference] = {"isa": isa, **values}
    return reference


def encode(value, indent: int = 0) -> str:
    padding = "\t" * indent
    if isinstance(value, dict):
        rows = [f"{padding}\t{json.dumps(str(key))} = {encode(item, indent + 1)};" for key, item in value.items()]
        return "{\n" + "\n".join(rows) + "\n" + padding + "}"
    if isinstance(value, list):
        return "(\n" + "\n".join(f"{padding}\t{encode(item, indent + 1)}," for item in value) + "\n" + padding + ")"
    if isinstance(value, int):
        return str(value)
    return json.dumps(str(value))


def source_files(patterns: list[str]) -> list[Path]:
    return sorted({path for pattern in patterns for path in ROOT.glob(pattern)})


def source_group(name: str, paths: list[Path]) -> tuple[str, str]:
    references = []
    build_files = []
    for path in paths:
        relative = path.relative_to(ROOT).as_posix()
        reference = add(f"file:{relative}", "PBXFileReference", lastKnownFileType="sourcecode.swift", path=relative, sourceTree="SOURCE_ROOT")
        references.append(reference)
        build_files.append(add(f"build:{name}:{relative}", "PBXBuildFile", fileRef=reference))
    group = add(f"group:{name}", "PBXGroup", children=references, name=name, sourceTree="<group>")
    sources = add(f"sources:{name}", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=build_files, runOnlyForDeploymentPostprocessing=0)
    return group, sources


def configurations(name: str, common: dict, debug: dict | None = None, release: dict | None = None) -> str:
    references = []
    for configuration, extra in [("Debug", debug or {}), ("Release", release or {})]:
        references.append(add(f"configuration:{name}:{configuration}", "XCBuildConfiguration", buildSettings={**common, **extra}, name=configuration))
    return add(f"configurations:{name}", "XCConfigurationList", buildConfigurations=references, defaultConfigurationIsVisible=0, defaultConfigurationName="Release")


def buildable(parent: ET.Element, target: str, filename: str, blueprint: str) -> None:
    ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=identifier(target), BuildableName=filename, BlueprintName=blueprint, ReferencedContainer="container:DeepWork.xcodeproj")


def main() -> None:
    app_paths = source_files(["DeepWork/App/**/*.swift", "DeepWork/Features/**/*.swift"])
    test_paths = source_files(["DeepWorkTests/Core/**/*.swift"])
    if not app_paths or not test_paths or not (ROOT / "Package.swift").is_file():
        raise SystemExit("Application sources, core tests and Package.swift must exist before generating the project.")
    app_group, app_sources = source_group("Application", app_paths)
    tests_group, test_sources = source_group("Core tests", test_paths)
    plist = add("file:Info.plist", "PBXFileReference", lastKnownFileType="text.plist.xml", path="DeepWork/Resources/Info.plist", sourceTree="SOURCE_ROOT")
    icons = add("file:Assets.xcassets", "PBXFileReference", lastKnownFileType="folder.assetcatalog", path="DeepWork/Resources/Assets.xcassets", sourceTree="SOURCE_ROOT")
    icons_build = add("build:Assets.xcassets", "PBXBuildFile", fileRef=icons)
    app_product = add("product:DeepWork", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0, path="Deep Work.app", sourceTree="BUILT_PRODUCTS_DIR")
    test_product = add("product:DeepWorkCoreTests", "PBXFileReference", explicitFileType="wrapper.cfbundle", includeInIndex=0, path="DeepWorkCoreTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
    products = add("group:Products", "PBXGroup", children=[app_product, test_product], name="Products", sourceTree="<group>")
    main_group = add("group:Main", "PBXGroup", children=[app_group, tests_group, plist, icons, products], sourceTree="<group>")
    package = add("package:DeepWorkCore", "XCLocalSwiftPackageReference", relativePath=".")

    common = {
        "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
        "MACOSX_DEPLOYMENT_TARGET": "15.0", "SDKROOT": "macosx",
        "ARCHS": "arm64", "EXCLUDED_ARCHS": "x86_64",
        "SUPPORTED_PLATFORMS": "macosx", "SWIFT_VERSION": "5.0",
        "GCC_C_LANGUAGE_STANDARD": "gnu17", "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES", "SWIFT_STRICT_CONCURRENCY": "complete",
    }
    project_configs = configurations("Project", common,
        {"DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES", "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"], "ONLY_ACTIVE_ARCH": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG", "SWIFT_OPTIMIZATION_LEVEL": "-Onone"},
        {"DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "SWIFT_COMPILATION_MODE": "wholemodule", "SWIFT_OPTIMIZATION_LEVEL": "-O"})

    targets = []
    target_settings = [
        ("DeepWork", app_sources, app_product, "com.apple.product-type.application", {
            "PRODUCT_NAME": "Deep Work", "PRODUCT_MODULE_NAME": "DeepWorkApp", "EXECUTABLE_NAME": "DeepWork",
            "PRODUCT_BUNDLE_IDENTIFIER": "app.deepwork.mac", "INFOPLIST_FILE": "DeepWork/Resources/Info.plist",
            "GENERATE_INFOPLIST_FILE": "NO", "CODE_SIGN_STYLE": "Automatic", "CODE_SIGN_IDENTITY": "-",
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"],
            "COMBINE_HIDPI_IMAGES": "YES", "ENABLE_APP_SANDBOX": "NO",
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        }),
        ("DeepWorkCoreTests", test_sources, test_product, "com.apple.product-type.bundle.unit-test", {
            "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_MODULE_NAME": "DeepWorkCoreTests",
            "PRODUCT_BUNDLE_IDENTIFIER": "app.deepwork.mac.core-tests", "GENERATE_INFOPLIST_FILE": "YES",
            "CODE_SIGN_STYLE": "Automatic", "CODE_SIGN_IDENTITY": "-",
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks", "@loader_path/../Frameworks"],
        }),
    ]
    for name, sources, product, product_type, settings in target_settings:
        dependency = add(f"dependency:{name}:DeepWorkCore", "XCSwiftPackageProductDependency", package=package, productName="DeepWorkCore")
        framework = add(f"framework:{name}:DeepWorkCore", "PBXBuildFile", productRef=dependency)
        frameworks = add(f"frameworks:{name}", "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[framework], runOnlyForDeploymentPostprocessing=0)
        resources = add(f"resources:{name}", "PBXResourcesBuildPhase", buildActionMask=2147483647, files=[icons_build] if name == "DeepWork" else [], runOnlyForDeploymentPostprocessing=0)
        build_phases = [sources, frameworks, resources]
        target_config = configurations(name, settings)
        targets.append(add(f"target:{name}", "PBXNativeTarget", buildConfigurationList=target_config, buildPhases=build_phases, buildRules=[], dependencies=[], name=name, packageProductDependencies=[dependency], productName="Deep Work" if name == "DeepWork" else name, productReference=product, productType=product_type))

    project = add("project", "PBXProject", attributes={"BuildIndependentTargetsInParallel": "YES", "LastUpgradeCheck": "1600", "TargetAttributes": {target: {"CreatedOnToolsVersion": "16.0", "ProvisioningStyle": "Automatic"} for target in targets}}, buildConfigurationList=project_configs, compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings=0, knownRegions=["en", "Base"], mainGroup=main_group, packageReferences=[package], productRefGroup=products, projectDirPath="", projectRoot="", targets=targets)
    PROJECT.mkdir(exist_ok=True)
    payload = {"archiveVersion": 1, "classes": {}, "objectVersion": 56, "objects": objects, "rootObject": project}
    (PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode(payload) + "\n")

    scheme = ET.Element("Scheme", LastUpgradeVersion="1600", version="1.3")
    build = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
    entries = ET.SubElement(build, "BuildActionEntries")
    for name, filename in [("DeepWork", "Deep Work.app"), ("DeepWorkCoreTests", "DeepWorkCoreTests.xctest")]:
        app = name == "DeepWork"
        entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES" if app else "NO", buildForProfiling="YES" if app else "NO", buildForArchiving="YES" if app else "NO", buildForAnalyzing="YES")
        buildable(entry, f"target:{name}", filename, name)
    test = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
    testables = ET.SubElement(test, "Testables")
    buildable(ET.SubElement(testables, "TestableReference", skipped="NO"), "target:DeepWorkCoreTests", "DeepWorkCoreTests.xctest", "DeepWorkCoreTests")
    launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB", selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO", ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", debugServiceExtension="internal", allowLocationSimulation="YES")
    buildable(ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"), "target:DeepWork", "Deep Work.app", "DeepWork")
    profile = ET.SubElement(scheme, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES", savedToolIdentifier="", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
    buildable(ET.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0"), "target:DeepWork", "Deep Work.app", "DeepWork")
    ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
    ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
    schemes = PROJECT / "xcshareddata" / "xcschemes"
    schemes.mkdir(parents=True, exist_ok=True)
    ET.indent(scheme, space="   ")
    ET.ElementTree(scheme).write(schemes / "DeepWork.xcscheme", encoding="UTF-8", xml_declaration=True)
    print(f"Generated {PROJECT.name}: {len(app_paths)} app sources, {len(test_paths)} core test sources.")


if __name__ == "__main__":
    main()
