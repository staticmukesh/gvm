#!/usr/bin/env bash

gvm_echo() {
  command printf %s\\n "$*" 2>/dev/null
}

gvm_current() {
    gvm_echo "current"
}

gvm_use() {
    gvm_echo "use"
}

gvm_install() {
    gvm_echo "install"
}

gvm_uninstall() {
    gvm_echo "uninstall"
}

gvm_help() {
    gvm_echo
    gvm_echo "Golang Version Manager"
    gvm_echo
    gvm_echo 'Usage:'
    gvm_echo '  gvm --help'
    gvm_echo '  gvm --version'
    gvm_echo '  gvm install <version>'
    gvm_echo '  gvm uninstall <version>'
    gvm_echo '  gvm use <version>'
    gvm_echo '  gvm ls'
    gvm_echo
    gvm_echo 'Example:'
    gvm_echo ' gvm install 1.11.0'
    gvm_echo ' gvm uninstall 1.11.0'
    gvm_echo ' gvm use 1.11.0'
    gvm_echo
    gvm_echo 'Note:'
    gvm_echo ' to remove, delete or uninstall gvm - just remove the $GVM_DIR folder (usually `~/.gvm`)'
}

gvm() {
    if [ $# -lt 1 ]; then
        gvm --help
        return
    fi

    local COMMAND
    COMMAND="${1-}"
    shift

    case $COMMAND in
        'help' | '--help' )
            gvm_help
        ;;
    esac
}

gvm