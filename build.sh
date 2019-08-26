#!/bin/bash
# vim: set sw=4 ts=4 sts=4 et:

set -eo pipefail

used_mktemp=false
: ${PNK_RPI_IMAGE_URL:="https://downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-2019-04-09/2019-04-08-raspbian-stretch-lite.zip"}
: ${PNK_RPI_IMAGE_SHA256SUM:="03ec326d45c6eb6cef848cf9a1d6c7315a9410b49a276a6b28e67a40b11fdfcf"}
: ${PNK_TEMP_DIR:="$(used_mktemp=true; mktemp -d)"}
: ${PNK_CACHE_DIR:="$PNK_TEMP_DIR/cache"}
: ${PNK_MOUNT_DIR:="$PNK_TEMP_DIR/mnt"}
: ${PNK_BUILD_DIR:="$PWD/build"}
: ${PNK_OUTPUT_FILE:="$PWD/build/pnk-$(date +%Y%m%dT%H%M%S).img"}
: ${PNK_EXTEND_MB:="0"}
: ${PNK_HOSTNAME:="pnk"}
: ${PNK_WORDPRESS_IMPORTER_URL:="https://downloads.wordpress.org/plugin/wordpress-importer.0.6.4.zip"}


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

    # Map sdcard partitions
    local output=( $(kpartx -s -a -v "$image") ) || {
        echo "Failed to map raspbian, invalid image?"
        return 1
    }

    # Extend size of image if requested
    if [[ "$PNK_EXTEND_MB" -gt 0 ]]; then
        e2fsck -f "/dev/mapper/${output[11]}" && resize2fs "/dev/mapper/${output[11]}" || {
            echo "Failed to resize filesystem."
            return 1
        }
    fi

    # Mount partitions
    printf "Mounting %s and %s at %s.\n" "${output[11]}" "${output[2]}" "$mount_dir"

    {
        mount "/dev/mapper/${output[11]}" "$mount_dir" && \
        mount "/dev/mapper/${output[2]}" "$mount_dir/boot/"
    } || {
        echo "Failed to mount chroot system directories."
        return 1
    }

    # If we resized the image, we may have changed the PARTUUID: workaround
    if [[ "$PNK_EXTEND_MB" -gt 0 ]]; then
        sed -i -e "s/PARTUUID=[a-zA-Z0-9]*-0/\/dev\/mmcblk0p/" "$mount_dir/boot/cmdline.txt"
        sed -i -e "s/PARTUUID=[a-zA-Z0-9]*-0/\/dev\/mmcblk0p/" "$mount_dir/etc/fstab"
    fi

    # Add static qemu so we can run ARM binaries
    cp "/usr/bin/qemu-arm-static" "$mount_dir/usr/bin"

    # enable SSH
    touch "$mount_dir/boot/ssh"

    # add shims since we can't start services
    systemd-nspawn --capability=all -D "$mount_dir" /bin/sh -c \
    "/usr/bin/dpkg-divert --add --rename --local /sbin/start-stop-daemon && \
    /usr/bin/dpkg-divert --add --rename --local /usr/sbin/policy-rc.d" || {
        echo "Failed to divert service tools."
        return 1
    }

cat <<'EOF' > "$mount_dir/sbin/start-stop-daemon"
#!/bin/sh
echo "Warning: Fake start-stop-daemon called, doing nothing"
EOF
    chmod +x "$mount_dir/sbin/start-stop-daemon"

cat <<'EOF' > "$mount_dir/usr/sbin/policy-rc.d"
#!/bin/sh
exit 101
EOF
    chmod +x "$mount_dir/usr/sbin/policy-rc.d"

    # Generate locales and install packages
    systemd-nspawn --capability=all -D "$mount_dir" /bin/sh -c \
    "echo en_US.UTF-8 UTF-8 > /etc/locale.gen && \
    /usr/sbin/locale-gen && \
    /usr/sbin/update-locale LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LC_ALL=en_US.UTF-8 && \
    apt-get -qq update && \
    apt-get install -y --no-install-recommends curl git libffi-dev python python-dev python-setuptools python-pip python-backports.ssl-match-hostname python-cffi python-nacl python-cryptography python-bcrypt python-paramiko" || {
        echo "Failed to initialize chroot locale and install dependencies."
        return 1
    }
}

setup_hostname() {
    local -r old_hostname="$1"
    local -r new_hostname="$2"
    local -r mount_dir="$3"

    sed -i -e "s/${old_hostname}/${new_hostname}/" "$mount_dir/etc/hosts"
    echo "$new_hostname" > "$mount_dir/etc/hostname"
}

setup_docker() {
    local -r domain="$1"
    local -r mount_dir="$2"

    # Install docker into chroot
    systemd-nspawn --capability=all -D "$mount_dir" /bin/sh -c "curl -sfL https://get.docker.com | sh" || {
        echo "Docker installation failed."
        return 1
    }

    # Install docker-compose into chroot
    systemd-nspawn --capability=all -D "$mount_dir" /bin/sh -c "pip install --no-cache-dir docker-compose" || {
        echo "Docker-compose installation failed."
        return 1
    }

    # Install docker-compose.yml into chroot
    mkdir -p "$mount_dir/etc/pnk"
    install -Dm644 "$PWD/docker-compose.yml" "$mount_dir/etc/pnk/"

    # Install and enable docker-start-all service
    install -Dm644 "$PWD/docker-start-all.service" "$mount_dir/etc/systemd/system/"
    ln -sf "/etc/systemd/system/docker-start-all.service" "$mount_dir/etc/systemd/system/multi-user.target.wants/docker-start-all.service"

    # Stop local docker
    service docker stop

    # Link docker directories into chroot
    rm -rf /var/lib/docker
    rm -rf /var/run/docker
    mkdir -p "$mount_dir/var/lib/docker"
    mkdir -p "$mount_dir/var/run/docker"
    ln -sf "$mount_dir/var/lib/docker" /var/lib/docker
    ln -sf "$mount_dir/var/run/docker" /var/run/docker

    # Start local docker
    service docker start
    
    # Template docker-compose file
    sed -i -e "s/{{ PNK_HOST }}/${domain}/g" "$PWD/docker-compose.yml"

    # Setup images
    docker-compose up --no-start || {
        echo "Docker image installation failed."
        return 1
    }
}

setup_configs() {
    local -r wp_url="$1"
    local -r mount_dir="$2"

    mkdir -p "$mount_dir/srv/"
    cp -rf "$PWD/configs/droppy" "$mount_dir/srv/"
    cp -rf "$PWD/configs/ngircd" "$mount_dir/srv/"
    cp -rf "$PWD/configs/thelounge" "$mount_dir/srv/"
    cp -rf "$PWD/configs/wordpress" "$mount_dir/srv/"
    curl -o "$mount_dir/srv/wordpress/wordpress-importer.zip" -L "$wp_url" ||
        { echo "Failed to download wordpress importer plugin."; return 1; }
}

cleanup() {
    # Remove shims
    rm "$PNK_MOUNT_DIR/sbin/start-stop-daemon"
    rm "$PNK_MOUNT_DIR/usr/sbin/policy-rc.d"
    systemd-nspawn --capability=all -D "$PNK_MOUNT_DIR" /bin/sh -c \
    "/usr/bin/dpkg-divert --remove --rename --local /sbin/start-stop-daemon && \
    /usr/bin/dpkg-divert --remove --rename --local /usr/sbin/policy-rc.d"

    # Unmount & clean up
    service docker stop
    umount -R -f "$PNK_MOUNT_DIR"
    dmsetup remove_all
    [[ "$used_mktemp" == "true" ]] && rm -rf "$PNK_TEMP_DIR"
}

main() {
    trap "{ rc="$?"; cleanup || true; exit "$rc"; }" EXIT

    check_bin curl
    check_bin dmsetup
    check_bin docker-compose
    check_bin kpartx
    check_bin ln
    check_bin mkdir
    check_bin mount
    check_bin mv
    check_bin parted
    check_bin resize2fs
    check_bin rm
    check_bin sed
    check_bin service
    check_bin sha256sum
    check_bin systemd-nspawn
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
    setup_configs "$PNK_WORDPRESS_IMPORTER_URL" "$PNK_MOUNT_DIR" || exit 1
    setup_hostname "raspberrypi" "$PNK_HOSTNAME" "$PNK_MOUNT_DIR" || exit 1
    setup_docker "$PNK_HOSTNAME" "$PNK_MOUNT_DIR" || exit 1

    mv "$PNK_TEMP_DIR/$image" "$PNK_OUTPUT_FILE" || exit 1
}

main "$@"

