# 15-mise.fish — single-source mise activation (cross-platform).
#
# Background:
#   Package installs of mise ship a fish vendor autoload at:
#     macOS Homebrew → /opt/homebrew/share/fish/vendor_conf.d/mise-activate.fish
#     Linux brew     → /home/linuxbrew/.linuxbrew/share/fish/vendor_conf.d/mise-activate.fish
#     Linux pkg mgr  → /usr/share/fish/vendor_conf.d/mise-activate.fish
#
#   Per fish docs, user conf.d ALWAYS runs before vendor_conf.d (the `zz-`
#   trick doesn't work — vendor isn't merged into user's alphabetical sort).
#   That means a vendor file always re-activates mise after the user file,
#   doubling the ~25ms cost.
#
# Fix:
#   We mask the vendor file with a same-basename symlink to /dev/null in
#   user conf.d (fish docs: "creating an empty file or symlink to /dev/null
#   with the same basename in their user conf.d directory" disables the
#   vendor file via dedup). See ./mise-activate.fish in this directory.
#
#   With vendor masked, this file becomes the single source of activation
#   and works for both package and self-installed mise on macOS or Linux.
#
# Refs:
#   https://github.com/fish-shell/fish-shell/issues/8553
#   https://fishshell.com/docs/current/language.html#configuration-files

if command -q mise
    mise activate fish | source
end
