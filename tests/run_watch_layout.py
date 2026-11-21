"""Run native iPad watch-layout regression checks in a booted iOS simulator.

Usage: python3 tests/run_watch_layout.py SIMULATOR_UDID
"""
import pathlib
import plistlib
import subprocess
import sys
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
def run(*args):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True)
    if result.returncode:
        sys.stderr.write(result.stdout + result.stderr)
        result.check_returncode()
    return result
with tempfile.TemporaryDirectory(prefix="youmod-surface-test-") as temp:
    app = pathlib.Path(temp) / "SurfaceTests.app"
    app.mkdir()
    sdk = run("xcrun", "--sdk", "iphonesimulator", "--show-sdk-path").stdout.strip()
    run("xcrun", "clang", "-target", "arm64-apple-ios17.0-simulator", "-isysroot", sdk,
        "-fobjc-arc", "-I", root / "CarPlay", "-framework", "UIKit", "-framework", "CarPlay",
        "-framework", "Foundation", "-framework", "CoreGraphics", root / "CarPlay/YCPWatchLayout.m", root / "CarPlay/YCPResponsiveLayout.m", root / "CarPlay/YCPBrowseLayout.m", root / "CarPlay/YCPHeaderLayout.m", root / "tests/watch_layout_harness.m",
        "-o", app / "SurfaceTests")
    (app / "Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "io.github.youtubecar.watch-layout-tests", "CFBundleExecutable": "SurfaceTests",
        "CFBundleName": "SurfaceTests", "CFBundlePackageType": "APPL", "CFBundleVersion": "1",
        "CFBundleShortVersionString": "1", "MinimumOSVersion": "17.0",
        "UIDeviceFamily": [1], "UILaunchScreen": {},
        # iOS 27 requires UIScene lifecycle adoption; the harness drives windows directly.
        "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False, "UISceneConfigurations": {
            "UIWindowSceneSessionRoleApplication": [{"UISceneConfigurationName": "Harness",
                "UISceneClassName": "UIWindowScene", "UISceneDelegateClassName": "HarnessSceneDelegate"}]}},
    }))
    run("codesign", "--force", "--sign", "-", app)
    run("xcrun", "simctl", "install", sys.argv[1], app)
    result = run("xcrun", "simctl", "launch", "--console", "--terminate-running-process", sys.argv[1], "io.github.youtubecar.watch-layout-tests")
    output = result.stdout + result.stderr
    if "WATCH_LAYOUT_TESTS_PASSED" not in output:
        raise RuntimeError(output)
    print("Responsive layout checks passed: seven screen sizes, mini-player bounds/aspect ratio, native split-metadata fix, watch layout, phone isolation, disconnect, search/metadata grid isolation, car header scroll/reveal configuration")
