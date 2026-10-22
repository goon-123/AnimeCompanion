#!/usr/bin/env python3
"""Rebuild the app-owned, test-only Kotlin continuation/reflection DEX (JDK 17)."""
import hashlib
from pathlib import Path
import subprocess
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / "Tools/MangaRuntime/target/probe-tool-cache"
ARTIFACTS = {
    "kotlin.zip": ("https://github.com/JetBrains/kotlin/releases/download/v2.1.0/kotlin-compiler-2.1.0.zip", "b6698d5728ad8f9edcdd01617d638073191d8a03139cc538a391b4e3759ad297"),
    "r8.jar": ("https://storage.googleapis.com/r8-releases/raw/8.12.28/r8.jar", "26b3bfa70ec1328b07c8d300ccf4bd933f53b9049927e42f424ec74c0f6351fc"),
}
with tempfile.TemporaryDirectory() as temporary:
    directory = Path(temporary)
    CACHE.mkdir(parents=True, exist_ok=True)
    for name, (url, digest) in ARTIFACTS.items():
        cached = CACHE / name
        if cached.exists():
            data = cached.read_bytes()
        else:
            with urllib.request.urlopen(url, timeout=120) as response:
                data = response.read()
            assert hashlib.sha256(data).hexdigest() == digest, name
            cached.write_bytes(data)
        assert hashlib.sha256(data).hexdigest() == digest, name
        (directory / name).write_bytes(data)
    with zipfile.ZipFile(directory / "kotlin.zip") as archive:
        archive.extractall(directory)
    subprocess.run(["java", "-cp", str(directory / "kotlinc/lib/kotlin-compiler.jar"), "org.jetbrains.kotlin.cli.jvm.K2JVMCompiler", "-kotlin-home", str(directory / "kotlinc"), "-classpath", str(directory / "kotlinc/lib/kotlinx-coroutines-core-jvm.jar"), "-jvm-target", "1.8", "-Xlambdas=class", "-d", str(directory / "probe.jar"), str(ROOT / "Tools/MangaRuntime/test-support/SharedJvmProbe.kt")], check=True)
    reference_classpath = str(directory / "probe.jar") + ":" + str(directory / "kotlinc/lib/kotlin-stdlib.jar") + ":" + str(directory / "kotlinc/lib/kotlinx-coroutines-core-jvm.jar")
    subprocess.run(["java", "-cp", reference_classpath, "app.animecompanion.probe.SharedJvmProbe"], check=True)
    subprocess.run(["java", "-cp", str(directory / "r8.jar"), "com.android.tools.r8.D8", "--min-api", "26", "--no-desugaring", "--lib", str(directory / "kotlinc/lib/kotlin-stdlib.jar"), "--output", str(directory / "probe.zip"), str(directory / "probe.jar")], check=True)
    with zipfile.ZipFile(directory / "probe.zip") as archive:
        data = archive.read("classes.dex")
    assert hashlib.sha256(data).hexdigest() == "11bc678a705469c525b3bdff11aedd045cf09894a15cb9ed994ec697f714d3db"
    (ROOT / "Tools/MangaRuntime/test-support/shared-jvm-probe.dex").write_bytes(data)
    print(hashlib.sha256(data).hexdigest())
