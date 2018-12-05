# -*- coding: utf-8 -*-
# vim: ft=sls

docker:
  pkg.installed:
    - pkgs:
      - python-docker
    - reload_modules: True

mariadb:
  docker_container.running:
    - name: mariadb
{% if grains['osarch'] != 'x86_64' %}
    - image: arm64v8/mariadb:10
{% else %}
    - image: mariadb:10
{% endif %}
    - restart_policy: always
    - environment:
      - MYSQL_RANDOM_ROOT_PASSWORD: yes
      - MYSQL_DATABASE: wordpress
      - MYSQL_USER: wordpress
      - MYSQL_PASSWORD: wordpress

wordpress:
  docker_container.running:
    - name: wordpress
{% if grains['osarch'] != 'x86_64' %}
    - image: arm64v8/wordpress:4
{% else %}
    - image: wordpress:4
{% endif %}
    - port_bindings:
      - 80
    - links:
      - mariadb:db
    - restart_policy: always
    - environment:
      - WORDPRESS_DB_HOST: db:3306
      - WORDPRESS_DB_USER: wordpress
      - WORDPRESS_DB_PASSWORD: wordpress
    - require:
      - docker_container: mariadb

unifi:
  docker_container.running:
    - name: unifi
    - restart_policy: always
{% if grains['osarch'] != 'x86_64' %}
    - imaage: ryansch/unifi-rpi:latest
    - binds:
      - unifi_config:/var/lib/unifi:rw
      - unifi_logs:/var/log/unifi:rw
{% else %}
    - image: jacobalberty/unifi:5.9
    - binds:
      - unifi_config:/unifi/data:rw
      - unifi_logs:/unifi/log:rw
{% endif %}
    - port_bindings:
      - 8080
      - 8443
      - 8843
      - 8880
      - 3478/udp
      - 6789
      - 10001/udp

unifi_config:
  docker_volume.present:
    - name: unifi_config
    - driver: local

unifi_logs:
  docker_volume.present:
    - name: unifi_logs
    - driver: local
