"""Count shared host-library references without treating presence as conformance."""
from collections import defaultdict

# First match wins, so specific components precede their parent namespaces.
FAMILIES = (
    ("Android browser", ("Landroid/webkit/",)),
    ("Android preferences", ("Landroidx/preference/", "Landroid/preference/")),
    ("Android platform", ("Landroid/", "Landroidx/")),
    ("OkHttp", ("Lokhttp3/",)),
    ("Okio", ("Lokio/",)),
    ("Jsoup", ("Lorg/jsoup/",)),
    ("JSON serialization", ("Lkotlinx/serialization/json/",)),
    ("Protobuf serialization", ("Lkotlinx/serialization/protobuf/",)),
    ("Serialization core", ("Lkotlinx/serialization/",)),
    ("Coroutines", ("Lkotlinx/coroutines/",)),
    ("Kotlin reflection", ("Lkotlin/reflect/", "Lkotlin/jvm/internal/Reflection")),
    ("Kotlin time", ("Lkotlin/time/",)),
    ("Kotlin standard library", ("Lkotlin/",)),
    ("Java cryptography and TLS", ("Ljava/security/", "Ljavax/crypto/", "Ljavax/net/ssl/")),
    ("Java date and locale", ("Ljava/time/", "Ljava/text/", "Ljava/util/Locale", "Ljava/util/TimeZone", "Ljava/util/Calendar", "Ljava/util/Date")),
    ("Java core", ("Ljava/", "Ljavax/")),
    ("Source framework", ("Leu/kanade/tachiyomi/", "Lkeiyoushi/")),
)


def family_for_class(descriptor):
    if descriptor.startswith("classAPI "):
        descriptor = "L" + descriptor[9:].replace(".", "/") + ";"
    descriptor = descriptor.split(" ", 1)[0]
    return next((name for name, prefixes in FAMILIES if descriptor.startswith(prefixes)), "Other")


def dependency_families(inventory):
    grouped = defaultdict(lambda: {"classes": set(), "methods": set()})
    for reference in inventory["references"] - inventory["declared"]:
        family = family_for_class(reference[0])
        if family != "Other":
            grouped[family]["classes"].add(reference[0])
            grouped[family]["methods"].add(reference)
    return {name: {"classes": len(values["classes"]), "methods": len(values["methods"])}
            for name, values in sorted(grouped.items())}


def dependency_summary(rows, observed):
    groups = defaultdict(lambda: {"packages": set(), "blockedPackages": set(), "observedAPIs": set()})
    for row in rows:
        for name in row.get("dependencyFamilies", {}):
            groups[name]["packages"].add(row["package"])
    for gap in observed:
        group = groups[family_for_class(gap["api"])]
        group["blockedPackages"].update(gap["packages"])
        group["observedAPIs"].add(gap["api"])
    return [{"family": name, "referencingPackages": len(group["packages"]),
             "blockedPackages": len(group["blockedPackages"]),
             "observedAPIs": sorted(group["observedAPIs"])}
            for name, group in sorted(groups.items(), key=lambda item: (
                -len(item[1]["blockedPackages"]), -len(item[1]["packages"]), item[0]))]
