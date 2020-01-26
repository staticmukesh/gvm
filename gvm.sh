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

gvm_init_cache_dir() {
   # create cache dir, if doesn't exist
   local cache_dir="${GVM_DIR}/.cache"
   if [ ! -d "${cache_dir}" ]; then
      command mkdir -p "${cache_dir}"
   fi
}

gvm_get_os() {
  local gvm_uname
  gvm_uname="$(command uname -a)"
  local gvm_os
  case "$gvm_uname" in
    Linux\ *) gvm_os=linux ;;
    Darwin\ *) gvm_os=darwin ;;
    SunOS\ *) gvm_os=sunos ;;
    FreeBSD\ *) gvm_os=freebsd ;;
    AIX\ *) gvm_os=aix ;;
  esac
  gvm_echo "${gvm_os-}"
}

gvm_get_arch() {
    local host_arch
    host_arch="$(command uname -m)"
  
    local gvm_arch
    case "$host_arch" in
        x86_64 | amd64) gvm_arch="amd64" ;;
        i*86) gvm_arch="386" ;;
        *) gvm_arch="$host_arch" ;;
    esac
    gvm_echo "${gvm_arch}"
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
    local artifact_name="$1"
    gvm_echo "https://dl.google.com/go/${artifact_name}"
}

gvm_releases_cache_file() {
	gvm_echo "$(gvm_cache_dir)/go_releases"
}

gvm_releases_parse() {
	grep -Po "https://dl.google.com/go/go[^>\"]+" $(gvm_releases_cache_file) | grep -Po "go[^/\-a-z]+" | sed -e "s/.$//g" | sed -e "s/^go//g" | sort -u
}

gvm_releases_update_cache() {
	curl --user-agent "gvm-release-cacher-$(gvm_version)"  -s https://golang.org/dl/ -o $(gvm_releases_cache_file)
}

gvm_releases_cache_ttl() {
	gvm_echo 3600
}

gvm_releases_cache_expired() {
	CACHE_LAST_CHANGE=$(stat `gvm_releases_cache_file` | grep Change | cut -d':' -f2- | sed -e "s/^[^0-9]*//g")
	CACHE_TS=$(date -d "${CACHE_LAST_CHANGE}" +"%s")
	NOW_TS=$(date +"%s")
	CACHE_AGE=$(expr $NOW_TS - $CACHE_TS)
	if [ $(gvm_releases_cache_ttl) -lt $CACHE_AGE ]; then
		return "1"
	else
		return "0"
	fi
}

gvm_releases() {
   gvm_init_cache_dir
   IS_CACHE=$([ -f $(gvm_releases_cache_file) ] && gvm_echo 1 || gvm_echo 0)
   CACHE_EXPIRED=$([ $IS_CACHE -eq 1 ] && gvm_releases_cache_expired; gvm_echo $?)
   [ $CACHE_EXPIRED -eq 0 ] || gvm_releases_update_cache
   gvm_releases_parse
}

gvm_flush() {
	rm $(gvm_releases_cache_file)
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

gvm_compute_checksum() {
    local file ="${1-}"

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
    [ -n "${1-}" ] && [ -x "$(gvm_go_version_dir "$1" 2> /dev/null)"/bin/go ]
}

gvm_grep() {
  GREP_OPTIONS='' command grep "$@"
}

gvm_add_path() {
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

gvm_strip_path() {
  if [ -z "${GVM_DIR-}" ]; then
    gvm_err '${GVM_DIR} not set!'
    return 1
  fi
  gvm_echo "${1-}" | command sed \
    -e "s#${GVM_DIR}/[^/]*${2-}[^:]*:##g" \
    -e "s#:${GVM_DIR}/[^/]*${2-}[^:]*##g" \
    -e "s#${GVM_DIR}/[^/]*${2-}[^:]*##g" \
    -e "s#${GVM_DIR}/versions/[^/]*/[^/]*${2-}[^:]*:##g" \
    -e "s#:${GVM_DIR}/versions/[^/]*/[^/]*${2-}[^:]*##g" \
    -e "s#${GVM_DIR}/versions/[^/]*/[^/]*${2-}[^:]*##g"
}

gvm_go_dir() {
    gvm_echo "${GVM_DIR}/versions/go"
}

gvm_go_version_dir() {
    local version="${1-}"
    if [ -z "${version}" ]; then
        gvm_err 'version is required'
        return 3
    else
        gvm_echo "$(gvm_go_dir)/${version}"
    fi
}

gvm_cache_dir() {
    gvm_echo "${GVM_DIR}/.cache"
}

gvm_is_cached() {
    local version="${1-}"
    if [ -z "${version}" ]; then
        gvm_err 'version is required'
        return 3
    fi

    local tarball=$(gvm_artifact_name ${version})
    local cached_path="$(gvm_cache_dir)/${tarball}"

    if [ -d $cached_path ]; then
        return 0
    else
        return 1
    fi
}

gvm_tree_contains_path() {
    local tree="${1-}"
    local install_path="${2-}"

    if [ "@${tree}@" = "@@" ] || [ "@${install_path}@" = "@@" ]; then
        gvm_err "both the tree and the path are required"
        return 2
    fi

    local pathdir="$(command dirname "${install_path}")"
    while [ "${pathdir}" != "" ] && [ "${pathdir}" != "." ] && [ "${pathdir}" != "/" ] && [ "${pathdir}" != "${tree}" ]; do
        pathdir=$(dirname "${pathdir}")
    done
    [ "${pathdir}" = "${tree}" ]
}

gvm_set_default() {
    [ -n "${1-}" ] && [ $(command echo "$1" 1> ${GVM_DIR}/default) ]
}

##########################################################

####################### Commands #########################

gvm_current() {
    local gvm_current_go_path
    if ! gvm_current_go_path="$(command which go 2> /dev/null)"; then
        gvm_echo 'none'
    elif gvm_tree_contains_path "${GVM_DIR}" "${gvm_current_go_path}"; then
        gvm_echo "$(go version 2>/dev/null)"
    else
        gvm_echo 'system'
    fi
}

gvm_use() {
    local version
    local gvm_use_silent

    while [ $# -ne 0 ]
        do
            case "$1" in
                '--silent')
                    gvm_use_silent=1
                ;;
                * )
                    version="$1"
                ;;
            esac
        shift
    done

    if [ -z $version ]; then
        gvm_err 'Please provife a version to use.'
        return 1
    fi

    if [ "_$version" = "_system" ]; then
        gvm_deactivate
        gvm_set_default "$version"
        [ -z "${gvm_use_silent}" ] && gvm_echo "Now using system's go"
        return
    fi

    local version_path="$(gvm_go_version_dir ${version})"
    if [ ! -d $version_path ]; then
        gvm_echo "Please install ${version} first to use it."
        return
    fi

    PATH="$(gvm_add_path "$PATH" "/bin" $version_path )"
    export PATH
    hash -r

    gvm_set_default "$version"
    [ -z "${gvm_use_silent}" ] && gvm_echo "Now using go ${version}"
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

    gvm_init_cache_dir

    gvm_echo "Downloading and installing go ${version}..."
    local artifact_name=$(gvm_artifact_name ${version})

    # checking tarball in cache
    if gvm_is_cached "${artifact_name}"; then
        gvm_echo "${artifact_name} has already been download."
    else
        local download_link="$(gvm_download_link ${artifact_name})"
        local is_download_failed=0
        gvm_echo "Downloading ${download_link}..."
        gvm_download -L -C - --progress-bar "${download_link}" -o "${cache_dir}/${artifact_name}" || is_download_failed=1
        
        if [ $is_download_failed -eq 1 ]; then
            command rm -rf "${cache_dir}/${artifact_name}"
            gvm_err "Binary download from ${download_link} failed."
            return 1
        fi
    fi

    # compute checksum
    # todo: fix it
    # gvm_compute_checksum "${cache_dir}/${artifact_name}"

    # extract tarball at required path
    local version_path="$(gvm_go_version_dir "${version}")"

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
    local version_path="$(gvm_go_version_dir "${version}")"

    if [ ! -d "${version_path}" ]; then
        gvm_err "go ${version} is not installed."
        return 1
    fi

    gvm_echo "Uninstalling go ${version} ..."
    command rm -rf "${version_path}"
    
    gvm deactivate
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
    gvm_echo '  gvm releases                    Display available release versions to install'
    gvm_echo '  gvm flush                       Remove the cache file used in gvm releases'
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

gvm_ls() {
    local versions
    local version_path=$(gvm_go_dir)
    if [ -d $version_path ]; then
        versions=$(command ls -A1 ${version_path})
        if [ ! -z ${#versions} ]; then
            gvm_echo $versions
        fi
    fi

    # check whether go has been installed
    if [ "$(command which go 2> /dev/null)" ]; then
        gvm_echo 'system'
    fi
}

gvm_version() {
    gvm_echo 'v0.1.1'
}

gvm_deactivate() {
    local NEWPATH="$(gvm_strip_path "$PATH" "/bin")"
    export PATH="$NEWPATH"
    hash -r
}

gvm_auto() {
    export GVM_DIR="$HOME/.gvm" # todo: fix it
    local version=$(command cat ${GVM_DIR}/default 2> /dev/null)
    if [ ! -z "${version}" ]; then
        gvm_use $version --silent
    fi
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
        'current' )
            gvm_current "$@"
        ;;
        'ls' )
            gvm_ls
        ;;
        'flush' )
            gvm_flush
        ;;
        'releases' )
            gvm_releases
        ;;
        'deactivate' )
            gvm_deactivate
        ;;
        * )
            >&2 gvm --help
            return 127
        ;;
    esac
}

gvm_auto
