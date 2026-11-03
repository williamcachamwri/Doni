#!/bin/zsh
# Fetches the Telegram-iOS sources we use as a *specification* for design
# tokens. That repo is GPL-2.0: we read numbers out of it and never copy,
# translate or link its code, so the checkout lives outside the app's build
# graph — and deliberately outside this project directory, because it carries
# its own AGENTS.md/CLAUDE.md that would otherwise be read as instructions for
# this repository.
#
# A blobless sparse clone of only the paths we cite costs ~20 MB instead of
# the ~900 MB full checkout.
set -euo pipefail
REF="${DESIGN_REFERENCE:-$HOME/Library/Caches/Doni/Telegram-iOS-DesignReference}"
REMOTE=https://github.com/TelegramMessenger/Telegram-iOS
PATHS=(
  submodules/TelegramPresentationData/Sources
  submodules/TelegramUI/Sources
  submodules/TelegramUI/Components/AudioWaveformComponent
  submodules/TelegramUI/Components/MediaScrubberComponent
  submodules/TelegramUI/Components/MediaPlaybackHeaderPanelComponent
  submodules/TelegramUI/Components/Chat/ChatMessageInteractiveFileNode
  submodules/TelegramUI/Components/ChatTitleView
  submodules/AuthorizationUI/Sources
  submodules/AuthorizationUtils
  submodules/CodeInputView/Sources
  submodules/SolidRoundedButtonNode/Sources
  submodules/PresentationDataUtils/Sources
  submodules/Display/Source
  submodules/ChatListUI/Sources
  submodules/ItemListUI/Sources
  submodules/TabBarUI/Sources
  submodules/SearchBarNode/Sources
  submodules/AvatarNode/Sources
  submodules/TelegramStringFormatting/Sources
)

if [[ -d "$REF/.git" ]]; then
  echo "reference already at $REF ($(git -C "$REF" rev-parse --short HEAD))"
else
  git clone --quiet --filter=blob:none --no-checkout --depth 1 --sparse "$REMOTE" "$REF"
fi
git -C "$REF" sparse-checkout set "${PATHS[@]}"
git -C "$REF" checkout --quiet FETCH_HEAD 2>/dev/null || git -C "$REF" checkout --quiet HEAD
echo "reference head: $(git -C "$REF" log -1 --format='%h %ad' --date=short)"
for p in "${PATHS[@]}"; do
  [[ -e "$REF/$p" ]] && echo "  ok  $p" || echo "  MISSING $p"
done
