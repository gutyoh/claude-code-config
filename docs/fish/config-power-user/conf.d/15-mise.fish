# 15-mise.fish — mise (runtime version manager: Python, Node, Ruby, etc.)
#
# Note: brew's mise installs a vendor autoload at
#   /opt/homebrew/share/fish/vendor_conf.d/mise.fish
# which fires automatically. This file is defensive — only activates if
# the vendor autoload didn't run (idempotent).

if not functions -q mise; and test -x /opt/homebrew/bin/mise
    /opt/homebrew/bin/mise activate fish | source
end
