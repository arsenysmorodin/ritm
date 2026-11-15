#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
developer_dir="${DEVELOPER_DIR:-$(xcode-select -p)}"
clt_frameworks="$developer_dir/Library/Developer/Frameworks"
if [[ "$developer_dir" == */CommandLineTools && -d "$clt_frameworks/Testing.framework" ]]; then
    swift test --disable-xctest -Xswiftc -F -Xswiftc "$clt_frameworks" \
        -Xlinker -rpath -Xlinker "$clt_frameworks" \
        -Xlinker -rpath -Xlinker "$developer_dir/Library/Developer/usr/lib"
else
    swift test --disable-xctest
fi
