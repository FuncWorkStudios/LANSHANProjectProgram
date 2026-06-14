#!/bin/bash
# Regenerate Story_*.gd files from .txt story sources.
# Run: bash tempp/regen_stories.sh
# Edit .txt files in assets/plot/, then run this script to sync to .gd.

HEADER='extends RefCounted

const TEXT: String = """'

FOOTER='"""'

declare -A MAP=(
    ["intro"]="Story_Intro"
    ["chapter1"]="Story_Chapter1"
    ["chapter2"]="Story_Chapter2"
    ["chapter3"]="Story_Chapter3"
    ["chapter4"]="Story_Chapter4"
)

for txt_id in "${!MAP[@]}"; do
    gd_name="${MAP[$txt_id]}"
    txt_file="assets/plot/${txt_id}.txt"
    gd_file="scripts/${gd_name}.gd"

    if [ ! -f "$txt_file" ]; then
        echo "WARNING: $txt_file not found, skipping."
        continue
    fi

    echo "$HEADER" > "$gd_file"
    cat "$txt_file" >> "$gd_file"
    echo "$FOOTER" >> "$gd_file"
    echo "Regenerated: $gd_file <- $txt_file"
done

echo "Done."
