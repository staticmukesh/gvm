#!/usr/bin/env bash

gvm_echo() {
  command printf %s\\n "$*" 2>/dev/null
}

gvm_has() {
    type "$1" > /dev/null 2>&1
}

gvm_install_dir() {
    command printf %s "${GVM_DIR:-"$HOME/.gvm"}"
}

gvm_latest_version() {
    gvm_echo "v0.1.0"
}

gvm_source() {
    local gvm_method="$1"
    local gvm_source_url
    if [ "_$gvm_method" = "_script" ]; then
        gvm_source_url="https://raw.githubusercontent.com/staticmukesh/gvm/$(gvm_latest_version)/gvm.sh"
    elif [ "_$gvm_method" = "_git" ] || [ -z "$gvm_method" ]; then
        gvm_source_url="https://github.com/staticmukesh/gvm.git"
    else
        echo >&2 "Unexpected value \"$gvm_method\" for \$gvm_method"
        return 1
    fi
    gvm_echo "$gvm_source_url"
}

gvm_download() {
    if gvm_has "curl"; then
        eval curl --fail  -q "$@"
    elif gvm_has "wget"; then
        ARGS=$(gvm_echo "$@" | command sed -e 's/--progress-bar /--progress=bar /' \
                        -e 's/--compressed //' \
                        -e 's/--fail //' \
                        -e 's/-L //' \
                        -e 's/-I /--server-response /' \
                        -e 's/-s /-q /' \
                        -e 's/-sS /-nv /' \
                        -e 's/-o /-O /' \
                        -e 's/-C - /-c /')
        eval wget $ARGS
    fi
}

install_gvm_from_git() {
    local install_dir="$(gvm_install_dir)"

    if [ -d "$install_dir/.git" ]; then
        echo "=> gvm is already installed in $install_dir, trying to update using git"
        command printf '\r=> '
        command git --git-dir="$install_dir"/.git --work-tree="$install_dir" fetch origin tag "$(gvm_latest_version)" --depth=1 2> /dev/null || {
            echo >&2 "Failed to update gvm, run 'git fetch' in $install_dir yourself."
            exit 1
        }
    else
        # Cloning to $install_dir
        echo "=> Downloading gvm from git to '$install_dir'"
        command printf '\r=> '
        mkdir -p "${install_dir}"
        if [ "$(ls -A "${install_dir}")" ]; then
            command git init "${install_dir}" || {
                echo >&2 'Failed to initialize gvm repo. Please report this!'
                exit 2
            }
            command git --git-dir="${install_dir}/.git" remote add origin "$(gvm_source)" 2> /dev/null \
                || command git --git-dir="${install_dir}/.git" remote set-url origin "$(gvm_source)" || {
                echo >&2 'Failed to add remote "origin" (or set the URL). Please report this!'
                exit 2
            }
            command git --git-dir="${install_dir}/.git" fetch origin tag "$(gvm_latest_version)" --depth=1 || {
                echo >&2 'Failed to fetch origin with tags. Please report this!'
                exit 2
            }
        else
            command git -c advice.detachedHead=false clone "$(gvm_source)" -b "$(gvm_latest_version)" --depth=1 "${install_dir}" || {
                echo >&2 'Failed to clone gvm repo. Please report this!'
                exit 2
            }
        fi
    fi

    command git -c advice.detachedHead=false --git-dir="$install_dir"/.git --work-tree="$install_dir" checkout -f --quiet "$(gvm_latest_version)"
    if [ ! -z "$(command git --git-dir="$install_dir"/.git --work-tree="$install_dir" show-ref refs/heads/master)" ]; then
        if command git --git-dir="$install_dir"/.git --work-tree="$install_dir" branch --quiet 2>/dev/null; then
            command git --git-dir="$install_dir"/.git --work-tree="$install_dir" branch --quiet -D master >/dev/null 2>&1
        else
            echo >&2 "Your version of git is out of date. Please update it!"
            command git --git-dir="$install_dir"/.git --work-tree="$install_dir" branch -D master >/dev/null 2>&1
        fi
    fi

    echo "=> Compressing and cleaning up git repository"
    if ! command git --git-dir="$install_dir"/.git --work-tree="$install_dir" reflog expire --expire=now --all; then
        echo >&2 "Your version of git is out of date. Please update it!"
    fi
    if ! command git --git-dir="$install_dir"/.git --work-tree="$install_dir" gc --auto --aggressive --prune=now ; then
        echo >&2 "Your version of git is out of date. Please update it!"
    fi
    return
}

install_gvm_as_script() {
    local install_dir="$(gvm_install_dir)"
    local gvm_source_local="$(gvm_source script)"

    mkdir -p "$install_dir"
    if [ -f "$install_dir/gvm.sh" ]; then
        echo "=> gvm is already installed in $install_dir, trying to update the script"
    else
        echo "=> Downloading gvm as script to '$install_dir'"
    fi
    gvm_download -s "$gvm_source_local" -o "$install_dir/gvm.sh" || {
        echo >&2 "Failed to download '$gvm_source_local'"
        return 1
    }
}

gvm_try_profile() {
  if [ -z "${1-}" ] || [ ! -f "${1}" ]; then
    return 1
  fi
  echo "${1}"
}

gvm_detect_profile() {
    if [ -n "${PROFILE}" ] && [ -f "${PROFILE}" ]; then
        echo "${PROFILE}"
        return
    fi

    local detected_profile=''
    if [ -n "${BASH_VERSION-}" ]; then
        if [ -f "$HOME/.bashrc" ]; then
            detected_profile="$HOME/.bashrc"
        elif [ -f "$HOME/.bash_profile" ]; then
            detected_profile="$HOME/.bash_profile"
        fi
    elif [ -n "${ZSH_VERSION-}" ]; then
        detected_profile="$HOME/.zshrc"
    fi

    if [ -z "$detected_profile" ]; then
        for EACH_PROFILE in ".profile" ".bashrc" ".bash_profile" ".zshrc"
            do
            if detected_profile="$(gvm_try_profile "${HOME}/${EACH_PROFILE}")"; then
                break
            fi
        done
    fi

    if [ ! -z "$detected_profile" ]; then
        echo "$detected_profile"
    fi
}

gvm_do_install() {
    if [ -n "${GVM_DIR-}" ] && ! [ -d "${GVM_DIR}" ]; then
        echo >&2 "You have \$GVM_DIR set to \"${GVM_DIR}\", but that directory does not exist. Check your profile files and environment."
        exit 1
    fi

    if [ -z "${METHOD}" ]; then
        if gvm_has git; then
            install_gvm_from_git
        elif gvm_has gvm_download; then
            install_gvm_as_script
        else
            echo >&2 'You need git, curl, or wget to install gvm'
            exit 1
        fi
    elif [ "${METHOD}" = 'git' ]; then
        if ! gvm_has git; then
            echo >&2 "You need git to install gvm"
            exit 1
        fi
        install_gvm_from_git
    elif [ "${METHOD}" = 'script' ]; then
        if ! gvm_has gvm_download; then
            echo >&2 "You need curl or wget to install gvm"
            exit 1
        fi
        install_gvm_as_script
    fi

    local gvm_profile="$(gvm_detect_profile)"
    local profile_install_dir="$(gvm_install_dir | command sed "s:^$HOME:\$HOME:")"

    local source_str="\\nexport GVM_DIR=\"${profile_install_dir}\"\\n[ -s \"\$GVM_DIR/gvm.sh\" ] && \\. \"\$GVM_DIR/gvm.sh\"  # This loads gvm\\n"

    if [ -z "${gvm_profile-}" ] ; then
        local tried_profile
        if [ -n "${PROFILE}" ]; then
            tried_profile="${gvm_profile} (as defined in \$PROFILE), "
        fi
        echo "=> Profile not found. Tried ${tried_profile-}~/.bashrc, ~/.bash_profile, ~/.zshrc, and ~/.profile."
        echo "=> Create one of them and run this script again"
        echo "   OR"
        echo "=> Append the following lines to the correct file yourself:"
        command printf "${source_str}"
        echo
    else
        if ! command grep -qc '/gvm.sh' "$gvm_profile"; then
            echo "=> Appending gvm source string to $gvm_profile"
            command printf "${source_str}" >> "$gvm_profile"
        else
            echo "=> gvm source string already in ${gvm_profile}"
        fi
    fi

    \. "$(gvm_install_dir)/gvm.sh"

    echo "=> Close and reopen your terminal to start using gvm or run the following to use it now:"
    command printf "${source_str}"
}

gvm_do_install

