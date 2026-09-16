#!/bin/bash
set -euo pipefail

VERSION="0.2.0"
CHANGELOG="Rebuilt for Jellyfin 12"
TARGET_ABI="12.0.0.0"
FRAMEWORK="net10.0"

# Releases live on their own branch; the manifest and the zips sit at its root.
BRANCH="release"
BASE_URL="https://raw.githubusercontent.com/wormi4ok/jellyfin-plugin-kinopoisk/$BRANCH"

BUILD_YAML="src/Jellyfin.Plugin.Kinopoisk/build.yaml"

check_command() {
    if ! command -v "$1" &> /dev/null
    then
        echo "Error: $1 could not be found. Please install it."
        exit 1
    fi
}

for cmd in gsed jq zip md5sum dotnet git; do check_command "$cmd"; done

cd "$(dirname "$0")"

find . -name project.assets.json -delete

gsed -i "s/^version: .*/version: \"$VERSION\"/" "$BUILD_YAML"
gsed -i "s/^targetAbi: .*/targetAbi: \"$TARGET_ABI\"/" "$BUILD_YAML"
gsed -i "s/^framework: .*/framework: \"$FRAMEWORK\"/" "$BUILD_YAML"
# changelog is a folded block and always last: truncate at its key, re-append the body
BUILDYAML=$(head -"$(grep -n "changelog: >" "$BUILD_YAML" | head -1 | cut -d: -f1)" "$BUILD_YAML")
printf '%s\n  %s\n' "$BUILDYAML" "$CHANGELOG" > "$BUILD_YAML"

dotnet restore ./src/Jellyfin.Plugin.Kinopoisk/
dotnet build --configuration Release ./src/Jellyfin.Plugin.Kinopoisk/

STAGING=$(mktemp -d)
WORKTREE=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
git worktree add --quiet "$WORKTREE" "$BRANCH"

cp "src/Jellyfin.Plugin.Kinopoisk/bin/Release/$FRAMEWORK/Jellyfin.Plugin.Kinopoisk.dll" "$STAGING/"
cp "src/KinopoiskUnofficialInfo.ApiClient/bin/Release/$FRAMEWORK/KinopoiskUnofficialInfo.ApiClient.dll" "$STAGING/"

TIMESTAMP=$(date -u "+%Y-%m-%dT%H:%M:%SZ")
cat << EOF > "$STAGING/meta.json"
{
    "category": "Metadata",
    "changelog": "$CHANGELOG",
    "description": "Загружает рейтинг, описания, актёров, трейлеры и т.д. с сайта КиноПоиск. Может потребоваться зарегистрировать свой ApiToken, см. информацию в параметрах плагина. Для точного распознавания рекомендуется указывать id фильма с сайта КиноПоиск в имени файла в формате kp-12345 или kp12345. Подробнее см. https://github.com/wormi4ok/jellyfin-plugin-kinopoisk/blob/master/README.md\n",
    "guid": "0c136f8a-ff77-4f2b-ade5-13462cae6216",
    "imageUrl": "https://kinopoisk.userecho.com/s/attachments/28876/0/1/25f8c0315e6ccb2aa6c2642e48f2c9e9.png",
    "name": "КиноПоиск",
    "overview": "Информация о фильмах и сериалах с КиноПоиска",
    "owner": "wormi4ok",
    "targetAbi": "$TARGET_ABI",
    "timestamp": "$TIMESTAMP",
    "version": "$VERSION"
}
EOF

ZIP="$WORKTREE/kinopoisk_$VERSION.zip"
rm -f "$ZIP"
( cd "$STAGING" && zip -jq "$ZIP" ./* )
HASH=$(md5sum "$ZIP" | cut -d' ' -f1)

jq --arg HASH "$HASH" \
   --arg URL "$BASE_URL/kinopoisk_$VERSION.zip" \
   --arg TIMESTAMP "$TIMESTAMP" \
   --arg VERSION "$VERSION" \
   --arg CHANGELOG "$CHANGELOG" \
   --arg TARGET_ABI "$TARGET_ABI" \
   '.[0].versions |= [{"version": $VERSION, "checksum": $HASH, "changelog": $CHANGELOG, "name": "КиноПоиск", "targetAbi": $TARGET_ABI, "sourceUrl": $URL, "timestamp": $TIMESTAMP}] + .' \
   "$WORKTREE/manifest.json" > "$WORKTREE/manifest.json.tmp"
mv "$WORKTREE/manifest.json.tmp" "$WORKTREE/manifest.json"

git -C "$WORKTREE" add "manifest.json" "kinopoisk_$VERSION.zip"
git -C "$WORKTREE" commit --quiet -m "Release $VERSION"
git worktree remove "$WORKTREE"

cat <<EOF

Committed $VERSION to the '$BRANCH' branch. Nothing has been pushed.

  git show $BRANCH
  git push origin $BRANCH

Commit $BUILD_YAML on this branch too.
EOF
