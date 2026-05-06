# Intentionally empty.
#
# This file masks the mise vendor autoload (which would otherwise re-activate
# mise after our 15-mise.fish, doubling the ~25ms cost) via fish's basename
# dedup: when ~/.config/fish/conf.d/<name>.fish and any vendor_conf.d/<name>.fish
# share a basename, the user file wins and the vendor file is skipped.
#
# Vendor file blocked:
#   /opt/homebrew/share/fish/vendor_conf.d/mise-activate.fish (macOS Homebrew)
#   /home/linuxbrew/.linuxbrew/share/fish/vendor_conf.d/mise-activate.fish (Linux brew)
#   /usr/share/fish/vendor_conf.d/mise-activate.fish (Linux pkg managers)
#
# Refs:
#   https://fishshell.com/docs/current/language.html#configuration-files
