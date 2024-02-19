#!/bin/bash

# Source directory (the directory to copy from)
SOURCE_DIR="dbt_packages/dbt_package_automations/new_package_files"

# Destination directory (the directory to copy to)
DEST_DIR="../dbt_$1"

# # Copy all contents from the source to the destination directory
# cp -R "$SOURCE_DIR"/* "$DEST_DIR"/

# # Copy all hidden from the source to the destination directory
# cp -R "$SOURCE_DIR"/.* "$DEST_DIR"/

# Phrases to be replaced
OLD_PHRASE1="package_name_here"
NEW_PHRASE1="$1"

OLD_PHRASE2="package_display_name"
NEW_PHRASE2="${2:-$NEW_PHRASE1}"

# Copy all contents from the source to the destination directory
cp -R "$SOURCE_DIR"/* "$DEST_DIR"/
cp -R "$SOURCE_DIR"/.* "$DEST_DIR"/ 2>/dev/null

# Use find to locate all files in the destination directory and use sed to replace the phrases
find "$DEST_DIR" -type f -exec sed -i '' "s/$OLD_PHRASE1/$NEW_PHRASE1/g" {} \;
find "$DEST_DIR" -type f -exec sed -i '' "s/$OLD_PHRASE2/$NEW_PHRASE2/g" {} \;

echo Populated standard package files