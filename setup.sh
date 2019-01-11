#!/bin/bash

set -eo pipefail

used_mktemp=false
PNK_CONTAINERS=( "arm64v8/mariadb:10" "arm64v8/wordpress:4" "ryansch/unifi-rpi:latest" )
: ${PNK_RPI_IMAGE_URL:="https://downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-2018-11-15/2018-11-13-raspbian-stretch-lite.zip"}
: ${PNK_RPI_IMAGE_SHA256SUM:="47ef1b2501d0e5002675a50b6868074e693f78829822eef64f3878487953234d"}
: ${PNK_SALT_SHA256SUM:="ab7f29b75711da4bb79aff98d46654f910d569ebe3e908753a3c5119017bb163"}
: ${PNK_TEMP_DIR:="$(used_mktemp=true; mktemp -d)"}
: ${PNK_CACHE_DIR:="$PNK_TEMP_DIR/cache"}
: ${PNK_MOUNT_DIR:="$PNK_TEMP_DIR/mnt"}
: ${PNK_BUILD_DIR:="$PWD/build"}


check_bin() {
    local -r cmd="$1"
    hash "$cmd" 2>/dev/null || { printf "Need command %s but it is not found. Aborting." "$cmd"; exit 1; }
}

setup_chroot() {
    local -r url="$1"
    local -r sha256sum="$2"
    local -r temp_dir="$3"
    local -r cache_dir="$4"
    local -r mount_dir="$5"
    # Download Raspbian
    if [[ ! -e "$cache_dir/raspbian.zip" ]]; then
        curl -o "$cache_dir/raspbian.zip" -L "$url" ||
            { echo "Failed to download raspbian."; return 1; }
    fi
    
    if ! ( echo "$sha256sum $cache_dir/raspbian.zip" | sha256sum -c ); then
        echo "Invalid checksum for raspbian image."
        rm -f "$cache_dir/raspbian.zip"
        return 1
    else
        unzip -d "$temp_dir" "$cache_dir/raspbian.zip" || {
            echo "Failed to unpack raspbian, invalid zip?"
            rm -f "$cache_dir/raspbian.zip"
            return 1
        }
    fi

    local image_pattern="$temp_dir/*.img"
    local image=( "$image_pattern" )
    kpartx -a -v "$image" || {
        echo "Failed to mount raspbian, invalid image?"
        return 1
    }

    {
        mount /dev/loop0p2 "$mount_dir" && \
        mount /dev/loop0p1 "$mount_dir/boot/" && \
        mount -t proc proc "$mount_dir/proc/" && \
        mount -t sysfs sys "$mount_dir/sys/" && \
        mount -o bind /dev "$mount_dir/dev/"
    } || {
        echo "Failed to mount chroot system directories."
        return 1
    }

    chroot "$mount_dir" bash -c \
    "echo en_US.UTF-8 UTF-8 > /etc/locale.gen && \
    /usr/sbin/locale-gen && \
    /usr/sbin/update-locale LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LC_ALL=en_US.UTF-8 && \
    apt-get -qq update && \
    apt-get install -y --no-install-recommends git python-pygit2" || {
        echo "Failed to initialize chroot locale and install dependencies."
        return 1
    }
}

setup_salt() {
    local -r sha256sum="$1"
    local -r mount_dir="$2"
    # Bootstrap salt
    if [[ ! -e "$mount_dir/bootstrap-salt.sh" ]]; then
        curl -o "$mount_dir/bootstrap-salt.sh" -L https://bootstrap.saltstack.com || \
            { echo "Failed to download salt-bootstrap script."; return 1; }
    fi
    
    if ! ( echo "$sha256sum $mount_dir/bootstrap-salt.sh" | sha256sum -c ); then
        echo "ERROR: Invalid checksum for Salt bootstrap script."
        rm -f "$mount_dir/bootstrap-salt.sh"
        return 1
    fi

    chroot "$mount_dir" bash -c "/bootstrap-salt.sh" || {
        echo "Salt-bootstrap execution failed."
        return 1
    }

    echo "file_client: local" > "$mount_dir/etc/salt/minion"
    mkdir -p "$mount_dir/srv/salt"
    cp -rf "$PWD/pillar" "$mount_dir/srv/"
    cp -rf "$PWD/pnk" "$mount_dir/srv/salt/"
    chroot "$mount_dir" salt-call state.highstate || {
        echo "Salt execution failed."
        return 1
    }
}

setup_docker() {
    local -a containers=( "${1[@]}" )
    local -r mount_dir="$2"
    local -i pulled=0
    mkdir -p "$mount_dir/srv/docker"
    for c in "${containers[@]}"; do
        docker pull "$c" || continue
        out="${$c/\//_/}"
        out="${$out/:/_/}"
        docker save -o "$mount_dir/srv/docker/$out.docker" "$c" && ((pulled++))
    done
    if [[ "${#containers[@]}" -ne "$pulled" ]]; then
        return 1
    fi
}

main() {
    trap "{ rc="$?"; umount -R -f "$PNK_MOUNT_DIR"; rm -rf "$PNK_TEMP_DIR"; exit "$?" }" EXIT

    check_bin curl
    check_bin docker
    check_bin kpartx
    check_bin mkdir
    check_bin mount
    check_bin rm
    check_bin sha256sum
    check_bin umount


    # Create build directories if they don't exist.
    local directories=( "$PNK_TEMP_DIR" "$PNK_CACHE_DIR" "$PNK_MOUNT_DIR" "$PNK_BUILD_DIR" )
    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir" || \
                { 
                    printf "Failed to create directory %s. Aborting" "$dir"
                    exit 1
                }
        fi
    done

    setup_chroot "$PNK_RPI_IMAGE_URL" "$PNK_RPI_IMAGE_SHA256SUM" "$PNK_TEMP_DIR" "$PNK_CACHE_DIR" "$PNK_MOUNT_DIR" || exit 1
    setup_salt "$PNK_SALT_SHA256SUM" "$PNK_MOUNT_DIR" || exit 1
    setup_docker "$PNK_CONTAINERS" "$PNK_MOUNT_DIR" || exit 1
}

main "$@"

