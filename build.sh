#!/bin/bash

set -eo pipefail

used_mktemp=false
PNK_CONTAINERS=( "arm64v8/mariadb:10" "arm64v8/wordpress:4" "ryansch/unifi-rpi:latest" )
: ${PNK_RPI_IMAGE_URL:="https://downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-2019-04-09/2019-04-08-raspbian-stretch-lite.zip"}
: ${PNK_RPI_IMAGE_SHA256SUM:="03ec326d45c6eb6cef848cf9a1d6c7315a9410b49a276a6b28e67a40b11fdfcf"}
: ${PNK_SALT_SHA256SUM:="46fb5e4b7815efafd69fd703f033fe86e7b584b6770f7e0b936995bcae1cedd8"}
: ${PNK_TEMP_DIR:="$(used_mktemp=true; mktemp -d)"}
: ${PNK_CACHE_DIR:="$PNK_TEMP_DIR/cache"}
: ${PNK_MOUNT_DIR:="$PNK_TEMP_DIR/mnt"}
: ${PNK_BUILD_DIR:="$PWD/build"}
: ${PNK_OUTPUT_FILE:="$PWD/build/pnk-$(date +%Y%m%dT%H%M%S).img"}
: ${PNK_EXTEND_MB:="0"}


check_bin() {
    local -r cmd="$1"
    hash "$cmd" 2>/dev/null || { printf "Need command %s but it is not found. Aborting." "$cmd"; exit 1; }
}

download_raspbian() {
    local -r url="$1"
    local -r sha256sum="$2"
    local -r cache_dir="$3"
    local -r temp_dir="$4"
    local -r file="${url##*/}"

    # Download Raspbian
    if [[ ! -e "$cache_dir/$file" ]]; then
        curl -o "$cache_dir/$file" -L "$url" ||
            { echo "Failed to download raspbian."; return 1; }
    fi
    
    if ! ( echo "$sha256sum $cache_dir/$file" | sha256sum -c ); then
        echo "Invalid checksum for raspbian image."
        rm -f "$cache_dir/$file"
        return 1
    else
        unzip -d "$temp_dir" "$cache_dir/$file" || {
            echo "Failed to unpack raspbian, invalid zip?"
            rm -f "$cache_dir/$file"
            return 1
        }
    fi
}

resize_image() {
    local -r image="$1"
    local -r extension="$2"

    truncate -s +"${extension}MB" "$image" || {
        echo "Failed to extend image."
        return 1
    }

    parted -s "$image" resizepart 2 100% || {
        echo "Failed to extend partition."
        return 1
    }
}



setup_chroot() {
    local -r image="$1"
    local -r mount_dir="$2"

    local output=( $(kpartx -s -a -v "$image") ) || {
        echo "Failed to map raspbian, invalid image?"
        return 1
    }

    if [[ "$PNK_EXTEND_MB" -gt 0 ]]; then
        e2fsck -f "/dev/mapper/${output[11]}" && resize2fs "/dev/mapper/${output[11]}" || {
            echo "Failed to resize filesystem."
            return 1
        }
    fi
    printf "Mounting %s and %s at %s.\n" "${output[11]}" "${output[2]}" "$mount_dir"

    {
        mount "/dev/mapper/${output[11]}" "$mount_dir" && \
        mount "/dev/mapper/${output[2]}" "$mount_dir/boot/" && \
        mount -t proc proc "$mount_dir/proc/" && \
        mount -t sysfs sys "$mount_dir/sys/" && \
        mount -t devtmpfs dev "$mount_dir/dev/" && \
        mount -t devpts devpts "$mount_dir/dev/pts"
    } || {
        echo "Failed to mount chroot system directories."
        return 1
    }

    cp "/usr/bin/qemu-arm-static" "$mount_dir/usr/bin"

    # enable SSH
    touch "$mount_dir/boot/ssh"
    
    chroot "$mount_dir" /usr/bin/env -i HOME="/root" TERM="$TERM" PATH="/bin:/usr/bin:/sbin:/usr/sbin" /bin/sh -c \
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

    chroot "$mount_dir" /usr/bin/env -i HOME="/root" TERM="$TERM" PATH="/bin:/usr/bin:/sbin:/usr/sbin" /bin/sh -c "/bin/chmod 775 /bootstrap-salt.sh && \
        /bootstrap-salt.sh -X -d" || {
        echo "Salt-bootstrap execution failed."
        return 1
    }

    echo "file_client: local" > "$mount_dir/etc/salt/minion"
    mkdir -p "$mount_dir/srv/salt"
    mkdir -p "$mount_dir/srv/pillar"
    cp -rf "$PWD"/pillar/* "$mount_dir/srv/pillar/"
    cp -rf "$PWD"/salt/* "$mount_dir/srv/salt/"
    chroot "$mount_dir" /usr/bin/env -i HOME="/root" TERM="$TERM" PATH="/bin:/usr/bin:/sbin:/usr/sbin" /bin/sh -c "/usr/bin/salt-call state.highstate" || {
        echo "Salt execution failed."
        return 1
    }
}

setup_docker() {
    local -r mount_dir="$1"
    shift
    local containers=( "$@" )
    local -i pulled=0
    mkdir -p "$mount_dir/srv/docker"
    for c in "${containers[@]}"; do
        docker pull "$c" || continue
        out="${c/\//_}"
        out="${out/:/_}"
        docker save -o "$mount_dir/srv/docker/$out.docker" "$c" && ((pulled++))
    done
    if [[ "${#containers[@]}" -ne "$pulled" ]]; then
        return 1
    fi
}

main() {
    trap "{ rc="$?"; umount -R -f "$PNK_MOUNT_DIR" || true; dmsetup remove_all || true; [[ "$used_mktemp" == "true" ]] && rm -rf "$PNK_TEMP_DIR" || true; exit "$rc"; }" EXIT

    check_bin curl
    check_bin dmsetup
    check_bin docker
    check_bin kpartx
    check_bin mkdir
    check_bin mount
    check_bin mv
    check_bin parted
    check_bin resize2fs
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

    local image="${PNK_RPI_IMAGE_URL##*/}"
    image="${image%.zip}.img"
    download_raspbian "$PNK_RPI_IMAGE_URL" "$PNK_RPI_IMAGE_SHA256SUM" "$PNK_CACHE_DIR" "$PNK_TEMP_DIR" || exit 1
    if [[ "$PNK_EXTEND_MB" -gt 0 ]];  then
        resize_image "$PNK_TEMP_DIR/$image" "$PNK_EXTEND_MB" || exit 1
    fi
    setup_chroot "$PNK_TEMP_DIR/$image" "$PNK_MOUNT_DIR" || exit 1
    setup_salt "$PNK_SALT_SHA256SUM" "$PNK_MOUNT_DIR" || exit 1
    setup_docker "$PNK_MOUNT_DIR" "${PNK_CONTAINERS[@]}" || exit 1

    ## Cleanup
    umount -R -f "$PNK_MOUNT_DIR"
    dmsetup remove_all
    [[ "$used_mktemp" == "true" ]] && rm -rf "$PNK_TEMP_DIR"

    mv "$PNK_TEMP_DIR/$image" "$PNK_OUTPUT_FILE" || exit 1
}

main "$@"

