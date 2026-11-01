"""Check that APK installation permissions are confined to the direct flavor."""

import argparse
import xml.etree.ElementTree as ET
from pathlib import Path

ANDROID = '{http://schemas.android.com/apk/res/android}'


def check(manifest: str, flavor: str) -> None:
    root = ET.fromstring(manifest)
    permissions = {item.get(ANDROID + 'name') for item in root.findall('uses-permission')}
    providers = {item.get(ANDROID + 'authorities') for item in root.findall('application/provider')}
    direct = flavor == 'direct'

    if ('android.permission.REQUEST_INSTALL_PACKAGES' in permissions) != direct:
        raise ValueError('Only direct APK builds may request package installation')

    if ('com.papyrus.reader.updates' in providers) != direct:
        raise ValueError('Only direct APK builds may expose update packages')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--flavor', choices=['play', 'direct'], required=True)
    args = parser.parse_args()
    check(args.manifest.read_text(), args.flavor)
