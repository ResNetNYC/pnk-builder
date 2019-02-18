# -*- coding: utf-8 -*-
# vim: ft=sls

Run Docker:
  service.running:
    - name: docker
    - require:
      - pkg: Install Docker and bindings

Mariadb load:
  docker_image.present:
    - name: arm64v8/mariadb
    - tag: 10
    - load: /srv/import/mariadb.docker
    - onlyif:
      - test -e /srv/import/mariadb.docker
    - require_in:
      - docker_container: Mariadb run

Mariadb run:
  docker_container.running:
    - name: mariadb
    - image: arm64v8/mariadb:10
    - restart_policy: always
    - environment:
      - MYSQL_RANDOM_ROOT_PASSWORD: yes
      - MYSQL_DATABASE: wordpress
      - MYSQL_USER: wordpress
      - MYSQL_PASSWORD: wordpress
    - require:
      - service: Run Docker

Wordpress load:
  docker_image.present:
    - name: arm64v8/wordpress
    - tag: 4
    - load: /srv/import/wordpress.docker
    - onlyif:
      - test -e /srv/import/wordpress.docker
    - require_in:
      - docker_container: Wordpress run

Wordpress run:
  docker_container.running:
    - name: wordpress
    - image: arm64v8/wordpress:4
    - port_bindings:
      - 80:80
    - links:
      - mariadb:db
    - restart_policy: always
    - environment:
      - WORDPRESS_DB_HOST: db:3306
      - WORDPRESS_DB_USER: wordpress
      - WORDPRESS_DB_PASSWORD: wordpress
    - require:
      - docker_container: mariadb
      - service: Run Docker

Unifi load:
  docker_image.present:
    - name: ryansch/unifi-rpi
    - tag: latest
    - load: /srv/import/unifi.docker
    - onlyif:
      - test -e /srv/import/unifi.docker
    - require_in:
      - docker_container: Unifi run

Unifi run:
  docker_container.running:
    - name: unifi
    - restart_policy: always
    - image: ryansch/unifi-rpi:latest
    - binds:
      - unifi_config:/var/lib/unifi:rw
      - unifi_logs:/var/log/unifi:rw
    - port_bindings:
      - 8080:8080
      - 8443:8443
      - 8843:8843
      - 8880:8880
      - 3478:3478/udp
      - 6789:6789
      - 10001:10001/udp
    - require:
      - service: Run Docker

unifi_config:
  docker_volume.present:
    - name: unifi_config
    - driver: local

unifi_logs:
  docker_volume.present:
    - name: unifi_logs
    - driver: local
