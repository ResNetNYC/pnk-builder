# -*- coding: utf-8 -*-
# vim: ft=sls

Set hostname:
  network.system:
    - enabled: True
    - hostname: pnkserver
    - apply_hostname: True
    - retain_settings: True

Install repo dependencies:
  pkg.installed:
    - pkgs:
      - apt-transport-https
      - ca-certificates
      - curl

Configure Unifi repository:
  pkgrepo.managed:
    - humanname: Unifi repo
    - name: deb http://www.ui.com/downloads/unifi/debian stable ubiquiti
    - file: /etc/apt/sources.list.d/100-ubnt-unifi.list
    - gpgcheck: 1
    - key_url: https://dl.ui.com/unifi/unifi-repo.gpg
    - require:
      - pkg: Install repo dependencies
    - require_in:
      - pkg: Unifi package

Unifi package:
  pkg.latest:
    - name: unifi
    - refresh: True

Configure saltroots:
  file.serialize:
    - name: /srv/salt/top.sls
    - makedirs: True
    - mode: 644
    - dataset:
        base:
          '*':
            - pnk_deploy
            - php
            - apache
            - mysql
            - wordpress
    - formatter: yaml

Deploy state:
  file.managed:
    - name: /srv/salt/pnk_deploy.sls
    - source: salt://pnk_deploy.sls
    - mode: 644
    - makedirs: True

Systemd unit:
  file.managed:
    - name: /etc/systemd/system/salt.service
    - source: salt://files/salt.service
    - user: root
    - group: root
    - mode: 644

Enable unit:
  file.symlink:
    - name: /etc/systemd/system/multi-user.target.wants/salt.service
    - target: /etc/systemd/system/salt.service
    - require:
      - file: Systemd unit
