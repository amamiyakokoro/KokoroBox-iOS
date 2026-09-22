#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 /path/to/circle-flags" >&2
    exit 64
fi

source_root=$1
source_flags="$source_root/flags"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(dirname -- "$script_dir")
destination="$repo_root/SFI/Assets.xcassets/CircleFlags"
license_destination="$repo_root/ThirdParty/circle-flags"

if [ ! -f "$source_flags/tw.svg" ] || [ ! -f "$source_root/LICENSE.md" ]; then
    echo "circle-flags source is incomplete: $source_root" >&2
    exit 65
fi

mkdir -p "$destination" "$license_destination"

printf '%s\n' \
    '{' \
    '  "info" : {' \
    '    "author" : "xcode",' \
    '    "version" : 1' \
    '  },' \
    '  "properties" : {' \
    '    "provides-namespace" : true' \
    '  }' \
    '}' > "$destination/Contents.json"

count=0
for source_file in "$source_flags"/??.svg; do
    code=$(basename -- "$source_file" .svg)
    asset_directory="$destination/$code.imageset"
    mkdir -p "$asset_directory"
    cp "$source_file" "$asset_directory/$code.svg"
    printf '%s\n' \
        '{' \
        '  "images" : [' \
        '    {' \
        "      \"filename\" : \"$code.svg\"," \
        '      "idiom" : "universal"' \
        '    }' \
        '  ],' \
        '  "info" : {' \
        '    "author" : "xcode",' \
        '    "version" : 1' \
        '  },' \
        '  "properties" : {' \
        '    "preserves-vector-representation" : true' \
        '  }' \
        '}' > "$asset_directory/Contents.json"
    count=$((count + 1))
done

if [ "$count" -lt 240 ]; then
    echo "expected at least 240 two-letter flags, imported $count" >&2
    exit 66
fi

cp "$source_root/LICENSE.md" "$license_destination/LICENSE.md"
revision=$(git -C "$source_root" rev-parse HEAD 2>/dev/null || printf '%s' unknown)
printf '%s\n' \
    '# circle-flags source' \
    '' \
    '- Repository: https://github.com/HatScripts/circle-flags' \
    "- Revision: $revision" \
    '- Imported files: two-letter SVG flags from `flags/`' \
    '- Destination: `SFI/Assets.xcassets/CircleFlags`' \
    > "$license_destination/SOURCE.md"

echo "Imported $count circle-flags assets."
