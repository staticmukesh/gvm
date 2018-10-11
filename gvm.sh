#!/usr/bin/env bash

########################## Utils ##########################
gvm_echo() {
  command printf %s\\n "$*" 2>/dev/null
}

gvm_err() {
  >&2 gvm_echo "$@"
}

gvm_has() {
  type "${1-}" > /dev/null 2>&1
}

gvm_get_os() {
  local GVM_UNAME
  GVM_UNAME="$(command uname -a)"
  local GVM_OS
  case "$GVM_UNAME" in
    Linux\ *) GVM_OS=linux ;;
    Darwin\ *) GVM_OS=darwin ;;
    SunOS\ *) GVM_OS=sunos ;;
    FreeBSD\ *) GVM_OS=freebsd ;;
    AIX\ *) GVM_OS=aix ;;
  esac
  gvm_echo "${GVM_OS-}"
}

gvm_get_arch() {
    local HOST_ARCH
    HOST_ARCH="$(command uname -m)"
  
    local GVM_ARCH
    case "$HOST_ARCH" in
        x86_64 | amd64) GVM_ARCH="amd64" ;;
        i*86) GVM_ARCH="386" ;;
        *) GVM_ARCH="$HOST_ARCH" ;;
    esac
    gvm_echo "${GVM_ARCH}"
}

gvm_artifact_name() {
    local version="${1-}"
    if [ -z "${version}" ]; then
        gvm_err 'version is required'
        return 3
    fi

    local gvm_os="$(gvm_get_os)"
    local gvm_arch="$(gvm_get_arch)"
    local artifact_name="go${version}.${gvm_os}-${gvm_arch}.tar.gz"

    gvm_echo "${artifact_name}"
}

gvm_download_link() {
    local ARTIFACT_NAME
    ARTIFACT_NAME="$1"

    local DOWNLOAD_URL
    GVM_DOWNLOAD_URL="https://dl.google.com/go/${ARTIFACT_NAME}"

    gvm_echo "${GVM_DOWNLOAD_URL}"
}

gvm_download() {
    local CURL_COMPRESSED_FLAG
    if gvm_has "curl"; then
        curl --fail  -q "$@"
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

gvm_compute_checksum() {
    local file 
    file="${1-}"

    if [ -z "${file}" ]; then
        gvm_err 'Provided file to checksum is empty'
        return 2
    elif ! [ -f "${file}" ]; then
        gvm_err 'Provided file to checksum does not exist.'
        return 1
    fi

    gvm_echo 'Computing checksum with shasum -a 256'
    command shasum -a 256 "${file}" | command awk '{print $1}'
}

gvm_is_version_installed() {
    [ -n "${1-}" ] && [ -x "$(gvm_version_path "$1" 2> /dev/null)"/bin/go ]
}

gvm_grep() {
  GREP_OPTIONS='' command grep "$@"
}

gvm_change_path() {
  if [ -z "${1-}" ]; then
    gvm_echo "${3-}${2-}"
  elif ! gvm_echo "${1-}" | gvm_grep -q "${GVM_DIR}/[^/]*${2-}" \
    && ! gvm_echo "${1-}" | gvm_grep -q "${GVM_DIR}/versions/[^/]*/[^/]*${2-}"; then
    gvm_echo "${3-}${2-}:${1-}"
  elif gvm_echo "${1-}" | gvm_grep -Eq "(^|:)(/usr(/local)?)?${2-}:.*${GVM_DIR}/[^/]*${2-}" \
    || gvm_echo "${1-}" | gvm_grep -Eq "(^|:)(/usr(/local)?)?${2-}:.*${GVM_DIR}/versions/[^/]*/[^/]*${2-}"; then
    gvm_echo "${3-}${2-}:${1-}"
  else
    gvm_echo "${1-}" | command sed \
      -e "s#${GVM_DIR}/[^/]*${2-}[^:]*#${3-}${2-}#" \
      -e "s#${GVM_DIR}/versions/[^/]*/[^/]*${2-}[^:]*#${3-}${2-}#"
  fi
}

gvm_version_path() {
    local version="${1-}"
    if [ -z "${version}" ]; then
        gvm_err 'version is required'
        return 3
    else
        gvm_echo "${GVM_DIR}/versions/go/${version}"
    fi
}

gvm_is_cached() {
    local version="${1-}"
    if [ -z "${version}" ]; then
        gvm_err 'version is required'
        return 3
    fi

    local tarball=$(gvm_artifact_name ${version})
    local cached_path="${GVM_CACHE_DIR}/${tarball}"

    if [ -d "${GVM_CACHE_DIR}/${tarball}" ]; then
        return 0
    else
        return 1
    fi
}

##########################################################

####################### Commands #########################

gvm_current() {
    gvm_echo "current"
}

gvm_use() {
    gvm_echo "use"
}

gvm_install() {
    if [ $# -lt 1 ]; then
        gvm_err 'Please provide a version to install.'
        return 1
    fi

    if ! gvm_has "curl" && ! gvm_has "wget"; then
        gvm_err 'gvm needs curl or wget to proceed.'
        return 1
    fi

    local version="${1-}"

    # check existence of version
    if gvm_is_version_installed "$version"; then
        gvm_err "go $version is already installed."
        # TODO use this version
        return 1
    fi

    # create cache dir, if doesn't exist
    local cache_dir="${GVM_DIR}/.cache"
    if [ ! -d "${cache_dir}" ]; then
        command mkdir -p "${cache_dir}"
    fi

    gvm_echo "Downloading and installing go ${version}..."
    local artifact_name=$(gvm_artifact_name ${version})

    # checking tarball in cache
    if gvm_is_cached "${artifact_name}"; then
        gvm_echo "${artifact_name} has already been download."
    else
        local download_link="$(gvm_download_link ${artifact_name})"
        gvm_echo "Downloading ${download_link}..."
        gvm_download -L -C - --progress-bar "${download_link}" -o "${cache_dir}/${artifact_name}" || (
            # remove partially downloaded tarball, in case of failure
            command rm -rf "${cache_dir}/${artifact_name}"
            gvm_err "Binary download from ${download_link} failed."
            exit 0
        )
    fi

    # compute checksum
    gvm_compute_checksum "${cache_dir}/${artifact_name}"

    # extract tarball at required path
    local version_path="$(gvm_version_path "${version}")"

    command mkdir -p "${version_path}"
    command tar -xf "${cache_dir}/${artifact_name}" -C "${version_path}" --strip-components 1

    # use the version
    gvm use "${version}"

    gvm_echo "go ${version} has been installed successfully."
}

gvm_uninstall() {
    if [ $# -lt 1 ]; then
        gvm_err 'Please provide a version to uninstall.'
        return 1
    fi

    local version="${1-}"
    local version_path="$(gvm_version_path "${version}")"

    if [ ! -d "${version_path}" ]; then
        gvm_err 'go ${version} is not installed.'
        return 1
    fi

    gvm_echo "Uninstalling go ${version} ..."
    command rm -rf "${version_path}"
    
    # TODO update PATH
    gvm_echo "go ${version} has been uninstalled successfully."
}

gvm_help() {
    gvm_echo
    gvm_echo "Golang Version Manager"
    gvm_echo
    gvm_echo 'Usage:'
    gvm_echo '  gvm --help                      Show this message'
    gvm_echo '  gvm --version                   Print out the installed version of gvm'          
    gvm_echo '  gvm install <version>           Download and install a <version>'
    gvm_echo '  gvm uninstall <version>         Uninstall a <version>'        
    gvm_echo '  gvm use <version>               Modify PATH to use <version>'
    gvm_echo '  gvm current                     Display currently activated version'
    gvm_echo '  gvm ls                          List installed versions'
    gvm_echo
    gvm_echo 'Example:'
    gvm_echo ' gvm install 1.11.0               Install a specific version number'
    gvm_echo ' gvm uninstall 1.11.0             Uninstall a specific version number'
    gvm_echo ' gvm use 1.11.0                   Use a specific version number'
    gvm_echo
    gvm_echo 'Note:'
    gvm_echo ' to remove, delete or uninstall gvm - just remove the $GVM_DIR folder (usually `~/.gvm`)'
    gvm_echo
}

gvm_version() {
    gvm_echo '0.1.0'
}

##########################################################

gvm() {
    if [ $# -lt 1 ]; then
        gvm --help
        return
    fi

    local COMMAND
    COMMAND="${1-}"
    shift

    case $COMMAND in
        'help' | '--help' | '-v' )
            gvm_help
        ;;
        'install' )
            gvm_install "$@"
        ;;
        'uninstall' )
            gvm_uninstall "$@"
        ;;
        'version' | '--version' ) 
            gvm_version
        ;;
        'use' )
            gvm_use "$@"
        ;;
        * )
            >&2 gvm --help
            return 127
        ;;
    esac
}

# Below mentioned lines are for testing only
GVM_DIR=$HOME/.gvm
mkdir -p $GVM_DIR
gvm "$@"