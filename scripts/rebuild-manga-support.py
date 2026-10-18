#!/usr/bin/env python3
"""Rebuild the small, Apache-2.0 Kotlin decoder boot-classpath dependency."""
import hashlib
from pathlib import Path
import subprocess
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = {
    "r8.jar": ("https://storage.googleapis.com/r8-releases/raw/8.12.28/r8.jar", "26b3bfa70ec1328b07c8d300ccf4bd933f53b9049927e42f424ec74c0f6351fc"),
    "serialization-protobuf.jar": ("https://repo.maven.apache.org/maven2/org/jetbrains/kotlinx/kotlinx-serialization-protobuf-jvm/1.9.0/kotlinx-serialization-protobuf-jvm-1.9.0.jar", "555035205ad1a21254b49fd6b5ddbe6ad1abb5c7baba244258bd758f80687bca"),
    "serialization-core.jar": ("https://repo.maven.apache.org/maven2/org/jetbrains/kotlinx/kotlinx-serialization-core-jvm/1.9.0/kotlinx-serialization-core-jvm-1.9.0.jar", "1f0afa172110e45a7231ef1b44ae8fd84c1ebaff96f3fc3ad68ef8c48120b59c"),
}
with tempfile.TemporaryDirectory() as temporary:
    directory = Path(temporary)
    for filename, (url, digest) in ARTIFACTS.items():
        with urllib.request.urlopen(url, timeout=120) as response:
            data = response.read()
        assert hashlib.sha256(data).hexdigest() == digest, filename
        (directory / filename).write_bytes(data)
    with zipfile.ZipFile(directory / "decoder.jar", "w") as output:
        for jar in ["serialization-core.jar", "serialization-protobuf.jar"]:
            with zipfile.ZipFile(directory / jar) as source:
                for name in source.namelist():
                    if name == "kotlinx/serialization/encoding/AbstractDecoder.class" or name.startswith(("kotlinx/serialization/descriptors/SerialKind", "kotlinx/serialization/descriptors/StructureKind", "kotlinx/serialization/descriptors/PrimitiveKind")) or name in ["kotlinx/serialization/protobuf/ProtoIntegerType.class", "kotlinx/serialization/protobuf/ProtoType.class", "kotlinx/serialization/protobuf/ProtoNumber.class"]:
                        if name.endswith(".class"): output.writestr(name, source.read(name))
    subprocess.run(["java", "-cp", str(directory / "r8.jar"), "com.android.tools.r8.D8", "--min-api", "26", "--no-desugaring", "--output", str(directory / "decoder.zip"), str(directory / "decoder.jar")], check=True)
    with zipfile.ZipFile(directory / "decoder.zip") as archive:
        data = archive.read("classes.dex")
    assert hashlib.sha256(data).hexdigest() == "0b01afdea1a52e6b760dcbabc858fbbdea73a3f8dac78049b20cce5681eb8ef5"
    (ROOT / "Tools/MangaRuntime/support/serialization-decoder.dex").write_bytes(data)

