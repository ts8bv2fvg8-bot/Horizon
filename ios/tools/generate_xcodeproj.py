#!/usr/bin/env python3
"""Writes ios/Horizon.xcodeproj from the files on disk.

Run from anywhere:  python3 ios/tools/generate_xcodeproj.py
Rerun after adding or removing source files outside Xcode (inside Xcode, just add files
normally). Object IDs are derived from file paths, so output is stable between runs.
"""
import hashlib
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent  # ios/
APP, TESTS = "Horizon", "HorizonTests"
BUNDLE_ID = "church.horizoncommunity.app"
DEPLOYMENT = "17.0"


def oid(*parts):
    return hashlib.md5("/".join(parts).encode()).hexdigest()[:24].upper()


def q(s):
    s = str(s)
    if s and all(c.isalnum() or c in "._/" for c in s) and not s[0].isdigit():
        return s
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


FILE_TYPES = {
    ".swift": "sourcecode.swift",
    ".plist": "text.plist.xml",
    ".xcassets": "folder.assetcatalog",
    ".xcconfig": "text.xcconfig",
}

objects = {}  # id -> (isa, dict)


def add(id_, isa, **fields):
    objects[id_] = (isa, fields)
    return id_


def walk(folder: Path, rel: str, sources: list, resources: list):
    """Creates a PBXGroup for `folder`, returning its id."""
    children = []
    for entry in sorted(folder.iterdir(), key=lambda p: (p.is_file() and p.suffix != ".xcassets", p.name.lower())):
        if entry.name.startswith("."):
            continue
        path = f"{rel}/{entry.name}"
        if entry.is_dir() and entry.suffix != ".xcassets":
            children.append(walk(entry, path, sources, resources))
            continue
        ftype = FILE_TYPES.get(entry.suffix)
        if not ftype:
            continue
        ref = add(oid("ref", path), "PBXFileReference", lastKnownFileType=ftype, path=entry.name, sourceTree="<group>")
        children.append(ref)
        if entry.suffix == ".swift":
            sources.append((path, ref))
        elif entry.suffix == ".xcassets":
            resources.append((path, ref))
    return add(oid("group", rel), "PBXGroup", children=children, path=folder.name, sourceTree="<group>")


app_sources, app_resources, test_sources = [], [], []
app_group = walk(ROOT / APP, APP, app_sources, app_resources)
tests_group = walk(ROOT / TESTS, TESTS, test_sources, [])

app_product = add(oid("product", APP), "PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0, path=f"{APP}.app", sourceTree="BUILT_PRODUCTS_DIR")
test_product = add(oid("product", TESTS), "PBXFileReference", explicitFileType="wrapper.cfbundle", includeInIndex=0, path=f"{TESTS}.xctest", sourceTree="BUILT_PRODUCTS_DIR")
products_group = add(oid("group", "Products"), "PBXGroup", children=[app_product, test_product], name="Products", sourceTree="<group>")
main_group = add(oid("group", "main"), "PBXGroup", children=[app_group, tests_group, products_group], sourceTree="<group>")

xcconfig_ref = oid("ref", f"{APP}/Config/Horizon.xcconfig")


def build_files(items, phase):
    return [add(oid("build", phase, path), "PBXBuildFile", fileRef=ref) for path, ref in items]


app_src_phase = add(oid("phase", APP, "sources"), "PBXSourcesBuildPhase", buildActionMask=2147483647, files=build_files(app_sources, "app-src"), runOnlyForDeploymentPostprocessing=0)
app_fw_phase = add(oid("phase", APP, "frameworks"), "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)
app_res_phase = add(oid("phase", APP, "resources"), "PBXResourcesBuildPhase", buildActionMask=2147483647, files=build_files(app_resources, "app-res"), runOnlyForDeploymentPostprocessing=0)
test_src_phase = add(oid("phase", TESTS, "sources"), "PBXSourcesBuildPhase", buildActionMask=2147483647, files=build_files(test_sources, "test-src"), runOnlyForDeploymentPostprocessing=0)
test_fw_phase = add(oid("phase", TESTS, "frameworks"), "PBXFrameworksBuildPhase", buildActionMask=2147483647, files=[], runOnlyForDeploymentPostprocessing=0)

common_project = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "GCC_C_LANGUAGE_STANDARD": "gnu17",
    "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT,
    "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
}
project_debug = {**common_project, "DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES", "GCC_OPTIMIZATION_LEVEL": "0",
                 "ONLY_ACTIVE_ARCH": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)", "SWIFT_OPTIMIZATION_LEVEL": "-Onone"}
project_release = {**common_project, "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "ENABLE_NS_ASSERTIONS": "NO",
                   "SWIFT_COMPILATION_MODE": "wholemodule", "VALIDATE_PRODUCT": "YES"}

app_settings = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": f"{APP}/Resources/Info.plist",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
    "MARKETING_VERSION": "1.0.0",
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "TARGETED_DEVICE_FAMILY": "1",
}
test_settings = {
    "BUNDLE_LOADER": "$(TEST_HOST)",
    "CODE_SIGN_STYLE": "Automatic",
    "GENERATE_INFOPLIST_FILE": "YES",
    "PRODUCT_BUNDLE_IDENTIFIER": f"{BUNDLE_ID}.tests",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "TARGETED_DEVICE_FAMILY": "1",
    "TEST_HOST": f"$(BUILT_PRODUCTS_DIR)/{APP}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{APP}",
}


def config_list(owner, debug, release, base=None):
    extra = {"baseConfigurationReference": base} if base else {}
    d = add(oid("cfg", owner, "Debug"), "XCBuildConfiguration", **extra, buildSettings=debug, name="Debug")
    r = add(oid("cfg", owner, "Release"), "XCBuildConfiguration", **extra, buildSettings=release, name="Release")
    return add(oid("cfglist", owner), "XCConfigurationList", buildConfigurations=[d, r], defaultConfigurationIsVisible=0, defaultConfigurationName="Release")


app_target = oid("target", APP)
test_target = oid("target", TESTS)
project_id = oid("project")

add(app_target, "PBXNativeTarget",
    buildConfigurationList=config_list(APP, app_settings, app_settings, base=xcconfig_ref),
    buildPhases=[app_src_phase, app_fw_phase, app_res_phase], buildRules=[], dependencies=[],
    name=APP, productName=APP, productReference=app_product, productType="com.apple.product-type.application")

proxy = add(oid("proxy", TESTS), "PBXContainerItemProxy", containerPortal=project_id, proxyType=1, remoteGlobalIDString=app_target, remoteInfo=APP)
dep = add(oid("dep", TESTS), "PBXTargetDependency", target=app_target, targetProxy=proxy)
add(test_target, "PBXNativeTarget",
    buildConfigurationList=config_list(TESTS, test_settings, test_settings),
    buildPhases=[test_src_phase, test_fw_phase], buildRules=[], dependencies=[dep],
    name=TESTS, productName=TESTS, productReference=test_product, productType="com.apple.product-type.bundle.unit-test")

add(project_id, "PBXProject",
    attributes={"BuildIndependentTargetsInParallel": 1, "LastSwiftUpdateCheck": 1600, "LastUpgradeCheck": 1600,
                "TargetAttributes": {app_target: {"CreatedOnToolsVersion": "16.0"},
                                     test_target: {"CreatedOnToolsVersion": "16.0", "TestTargetID": app_target}}},
    buildConfigurationList=config_list("project", project_debug, project_release),
    compatibilityVersion="Xcode 14.0", developmentRegion="en", hasScannedForEncodings=0,
    knownRegions=["en", "Base"], mainGroup=main_group, productRefGroup=products_group,
    projectDirPath="", projectRoot="", targets=[app_target, test_target])


def render(value, indent):
    pad = "\t" * indent
    if isinstance(value, dict):
        inner = "".join(f"{pad}\t{q(k)} = {render(v, indent + 1)};\n" for k, v in value.items())
        return "{\n" + inner + pad + "}"
    if isinstance(value, list):
        inner = "".join(f"{pad}\t{render(v, indent + 1)},\n" for v in value)
        return "(\n" + inner + pad + ")"
    return q(value)


out = ["// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {\n"]
for isa in sorted({isa for isa, _ in objects.values()}):
    out.append(f"\n/* Begin {isa} section */\n")
    for id_, (kind, fields) in sorted(objects.items()):
        if kind != isa:
            continue
        out.append(f"\t\t{id_} = {render({'isa': isa, **fields}, 2)};\n")
    out.append(f"/* End {isa} section */\n")
out.append(f"\t}};\n\trootObject = {project_id};\n}}\n")

proj = ROOT / f"{APP}.xcodeproj"
(proj / "project.xcworkspace" / "xcshareddata").mkdir(parents=True, exist_ok=True)
(proj / "project.pbxproj").write_text("".join(out))
(proj / "project.xcworkspace" / "contents.xcworkspacedata").write_text(
    '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n')
(proj / "project.xcworkspace" / "xcshareddata" / "IDEWorkspaceChecks.plist").write_text(
    '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    '<plist version="1.0">\n<dict>\n\t<key>IDEDidComputeMac32BitWarning</key>\n\t<true/>\n</dict>\n</plist>\n')

ref = lambda target, name, product: (
    f'               BuildableIdentifier = "primary"\n               BlueprintIdentifier = "{target}"\n'
    f'               BuildableName = "{product}"\n               BlueprintName = "{name}"\n'
    f'               ReferencedContainer = "container:{APP}.xcodeproj">')
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference
{ref(app_target, APP, APP + ".app")}
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference
{ref(test_target, TESTS, TESTS + ".xctest")}
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
{ref(app_target, APP, APP + ".app")}
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference
{ref(app_target, APP, APP + ".app")}
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''
(proj / "xcshareddata" / "xcschemes").mkdir(parents=True, exist_ok=True)
(proj / "xcshareddata" / "xcschemes" / f"{APP}.xcscheme").write_text(scheme)
print(f"Wrote {proj.relative_to(ROOT.parent)} ({len(app_sources)} app sources, {len(test_sources)} test sources)")
