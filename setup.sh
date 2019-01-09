#!/bin/bash

set -eo pipefail

declare -r IMAGE_URL="https://downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-2018-11-15/2018-11-13-raspbian-stretch-lite.zip"
declare -r IMAGE_SHA256SUM="47ef1b2501d0e5002675a50b6868074e693f78829822eef64f3878487953234d"

check_bin() {
    local cmd = "$1"
    hash "$cmd" 2>/dev/null || { printf "Need command %s but it is not found. Aborting." "$cmd"; exit 1; }
}

setup_chroot() {
    local mnt="$1"
    kpartx -a -v 
}

setup_salt() {
}

setup_docker() {
}

main() {
    check_bin curl
    check_bin docker
    check_bin kpartx
    check_bin mkdir
    check_bin mount
    check_bin rm
    check_bin sha256sum
    check_bin umount

    # Create build directories
    mkdir "$PWD/build"
    mkdir "$PWD/cache"
    local temp="$(mktemp -d)"
    mkdir "$temp/mnt"

    trap "{ umount -R -f "$temp"; rm -rf "$temp"; exit 0 }" EXIT
    
    # Pull Docker images
    docker pull arm64v8/mariadb:10
    docker pull arm64v8/wordpress:4
    docker pull ryansch/unifi-rpi:latest
    
    if [[ ! -e "$PWD/cache/raspbian.zip" ]]; then
        curl -o "$PWD/cache/raspbian.zip" -L "$IMAGE_URL"
    fi
    
    if ! ( echo "$IMAGE_SHA256SUM $PWD/cache/raspbian.zip" | sha256sum -c ); then
        echo "Invalid checksum for raspbian image. Aborting."
        rm -f "$PWD/cache/raspbian.zip"
        exit 1
    else
        unzip -d "$temp" "$PWD/cache/raspbian.zip"

        

    
    # Bootstrap salt
    curl -o bootstrap-salt.sh -L https://bootstrap.saltstack.com
    
    # Save Docker images
    mkdir import
    docker save -o import/mariadb.docker arm64v8/mariadb:10
    docker save -o import/wordpress.docker arm64v8/wordpress:4
    docker save -o import/unifi.docker ryansch/unifi-rpi:latest
}

