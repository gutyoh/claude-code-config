# 05-greeting.fish — silence the "Welcome to fish, the friendly interactive
# shell" message that fish prints on every new interactive shell.
#
# fish_greeting can be a string or a function. Setting it to an empty
# global var disables it entirely.
#
# To restore the default greeting, delete this file or run:
#     set -e fish_greeting

set -g fish_greeting ''
