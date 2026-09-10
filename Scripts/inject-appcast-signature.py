#!/usr/bin/env python3
"""Inject a Sparkle EdDSA signature into an appcast enclosure, deterministically.

Usage:
    inject-appcast-signature.py <appcast.xml> <base64-signature>

The signature is produced by Sparkle's `sign_update` (Ed25519 over the archive
bytes). This helper only ever writes the PUBLIC signature into the feed; it
never touches key material. The file is rewritten with a stable namespace and
2-space indentation so a regenerated feed has no formatting noise.
"""

import sys
import xml.etree.ElementTree as ET

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    path, signature = sys.argv[1], sys.argv[2]
    if not signature:
        print("empty signature", file=sys.stderr)
        return 1

    ET.register_namespace("sparkle", SPARKLE_NS)
    tree = ET.parse(path)
    channel = tree.getroot().find("channel")
    items = channel.findall("item") if channel is not None else []
    if len(items) != 1:
        print("expected exactly one <item>, found %d" % len(items), file=sys.stderr)
        return 1
    enclosure = items[0].find("enclosure")
    if enclosure is None:
        print("no <enclosure> in the appcast item", file=sys.stderr)
        return 1

    enclosure.set("{%s}edSignature" % SPARKLE_NS, signature)
    ET.indent(tree, space="    ")
    tree.write(path, encoding="utf-8", xml_declaration=True)
    print("signature injected (%d base64 chars)" % len(signature))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
