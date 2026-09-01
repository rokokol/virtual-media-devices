# Zsh completion for ./install.sh of virtual-media-devices. Sourced from the checkout,
# not installed:
#   source completions/install.sh.zsh
# Defines the function and registers it directly — no fpath, no rehash; needs compinit
# to have run, which every interactive zsh with completion already has.
#
# The flag list is written by hand on purpose and checked against install.sh by
# tests/check-completions.sh — same discipline as the bash file
_install_sh_completion() {
  _arguments \
    '(-h --help)'{-h,--help}'[show help and exit]' \
    '(-v --version)'{-v,--version}'[print the version and exit]' \
    '--prefix[install prefix]:directory:_files -/' \
    '--destdir[staging root]:directory:_files -/' \
    '--component[which command to install]:component:(cam mic all)' \
    '--uninstall[remove a previous install by its manifest]'
}
compdef _install_sh_completion install.sh
