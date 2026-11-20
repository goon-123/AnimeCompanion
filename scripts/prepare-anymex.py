#!/usr/bin/env python3
"""Prepare a pinned AnymeX dependency without accessing installed user data."""
import hashlib
import pathlib
import re
import shutil
import subprocess
import urllib.request
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
REVISION = '98402444842f5bc1ad85ac381401640af486fa2b'
UPSTREAM = ROOT / 'build/AnymeXBridge'
MODULE = ROOT / 'Tools/ExtensionBridge'
JAR_URL = 'https://github.com/RyanYuuki/AnymeXExtensionRuntimeBridge/releases/download/v2.7.4/anymex_desktop_runtime.jar'
JAR_SHA256 = 'cdbbe4836ccf8fc20ef3009372ebcd6d1af1ca8b591fa907fb3de7bdb6a0d782'


def replace_once(path, original, replacement):
    value = path.read_text()
    if replacement in value:
        return
    if value.count(original) != 1:
        raise RuntimeError(f'Pinned upstream changed: {path.name}')
    path.write_text(value.replace(original, replacement, 1))


def prepare():
    if not UPSTREAM.exists():
        UPSTREAM.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(['git', 'clone', 'https://github.com/RyanYuuki/AnymeXExtensionRuntimeBridge.git', str(UPSTREAM)], check=True)
        subprocess.run(['git', '-C', str(UPSTREAM), 'checkout', '--detach', REVISION], check=True)
    actual = subprocess.check_output(['git', '-C', str(UPSTREAM), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != REVISION:
        raise RuntimeError('The AnymeX checkout is not the pinned revision; use a clean build directory.')
    # Retain every source manager. Exclude the unused TorrServer native engine;
    # AnimeCompanion continues to resolve torrent playback through TorBox.
    pod = UPSTREAM / 'ios/anymex_extension_runtime_bridge.podspec'
    # Device JNI headers are supplied by the vendored OpenJDK framework. The
    # source tree also has two jni_md.h files, which collide in Copy Headers.
    replace_once(pod, '  s.public_header_files =', "  s.exclude_files = '**/TorrServerBridge.swift', '**/jdk/**'\n  s.public_header_files =")
    replace_once(pod, "    'anymex_extension_bridge/Frameworks/TorrServerKit.xcframework',", '    # Companion uses TorBox instead of TorrServer.')
    replace_once(pod, "s.prepare_command = 'sh PrepareEmbeddedRuntime.sh && sh PrepareTorrServerRuntime.sh'", "s.prepare_command = 'true' # Companion stages the pinned runtime.")
    plugin = UPSTREAM / 'ios/anymex_extension_bridge/Sources/anymex_extension_bridge/AnymexExtensionRuntimeBridgePlugin.swift'
    replace_once(plugin, '  private let torrServerBridge = TorrServerBridge()', '  // Companion uses TorBox for torrent playback.')
    replace_once(plugin, '    instance.torrServerBridge.attach(to: registrar)', '    // No TorrServer native channel is installed.')
    cloudstream = UPSTREAM / 'lib/Services/CloudStreamDesktop/DesktopCloudStreamSourceMethods.dart'
    replace_once(cloudstream, '      print("Detail response: $res");', '      // Companion does not log provider detail payloads.')
    manager = UPSTREAM / 'lib/ExtensionManager.dart'
    replace_once(manager, 'class ExtensionManager extends GetxController {',
        'class ExtensionManager extends GetxController {\n  ExtensionManager({this.automaticallyInitialize = true});\n  final bool automaticallyInitialize;')
    replace_once(manager, '    _initDefaultManagers();', '    if (automaticallyInitialize) _initDefaultManagers();')
    # Upstream includes a shared TMDB credential in Nuvio's optional metadata
    # fallback. Require a user's own optional source preference instead.
    nuvio = UPSTREAM / 'lib/Services/Nuvio/NuvioPluginSourceMethods.dart'
    value = nuvio.read_text()
    value = re.sub(r'api_key=[A-Za-z0-9]{24,}',
        "api_key=${Uri.encodeQueryComponent(getVal<String>('companion.tmdbApiKey', defaultValue: '') ?? '')}", value)
    value = re.sub(r"if \(tmdbId.startsWith\('tt'\)\) \{(\s+try \{\s+final findRes = await _httpClient.get\()",
        r"if (tmdbId.startsWith('tt') && (getVal<String>('companion.tmdbApiKey', defaultValue: '') ?? '').isNotEmpty) {\1", value)
    nuvio.write_text(value)
    frameworks = UPSTREAM / 'ios/anymex_extension_bridge/Frameworks'
    if not (frameworks / 'OpenJDKRuntime.xcframework').exists():
        with zipfile.ZipFile(frameworks / 'ios-runtime-v1/OpenJDKRuntime.xcframework.zip') as archive:
            archive.extractall(frameworks)
    for binary in (frameworks / 'OpenJDKRuntime.xcframework').glob('*/OpenJDKRuntime.framework/OpenJDKRuntime'):
        binary.chmod(0o755)
    assets = MODULE / 'assets'
    assets.mkdir(parents=True, exist_ok=True)
    jar = assets / 'anymex_desktop_runtime.jar'
    if not jar.exists() or hashlib.sha256(jar.read_bytes()).hexdigest() != JAR_SHA256:
        temporary = jar.with_suffix('.download')
        try:
            with urllib.request.urlopen(JAR_URL, timeout=120) as response, temporary.open('wb') as destination:
                shutil.copyfileobj(response, destination)
            if hashlib.sha256(temporary.read_bytes()).hexdigest() != JAR_SHA256:
                raise RuntimeError('The AnymeX backend checksum did not match.')
            temporary.replace(jar)
        finally:
            temporary.unlink(missing_ok=True)
    (ROOT / 'App/ExtensionRuntimeNotices.txt').write_text(
        'AnimeCompanion extension integration\n\n'
        f'AnymeX Extension Runtime Bridge: {REVISION}\n'
        'https://github.com/RyanYuuki/AnymeXExtensionRuntimeBridge\n'
        'Integration source and modifications: Tools/ExtensionBridge and scripts/prepare-anymex.py\n\n'
        + (UPSTREAM / 'LICENSE').read_text() + '\n\n'
        + (UPSTREAM / 'ios/RuntimeSources/THIRD_PARTY_NOTICES.md').read_text())
    print(f'Prepared AnymeX {REVISION[:12]} and verified backend v2.7.4.')


if __name__ == '__main__':
    prepare()
