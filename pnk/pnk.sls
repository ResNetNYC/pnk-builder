# -*- coding: utf-8 -*-
# vim: ft=sls

Install Docker repo dependencies:
  pkg.installed:
    - pkgs:
      - apt-transport-https
      - ca-certificates
      - curl

Setup Docker apt repository:
  pkgrepo.managed:
    - name: deb https://download.docker.com/linux/raspbian stretch edge
    - file: /etc/apt/sources.list.d/docker.list
    - require:
      - pkg: Install Docker repo dependencies
    - key_url: https://download.docker.com/linux/raspbian/gpg

Install Docker and bindings:
  pkg.installed:
    - pkgs:
      - docker-ce
      - python-docker
    - require:
      - pkgrepo: Setup Docker apt repository
    - reload_modules: True

Configure saltroots:
  file.serialize:
    - name: /srv/salt/top.sls
    - makedirs: True
    - mode: 644
    - dataset:
      base:
        '*':
          - pnk_deploy
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
    - source: salt://pnk/files/salt.service
    - user: root
    - group: root
    - mode: 644

Enable unit:
  file.symlink:
    - name: /etc/systemd/system/multi-user.target.wants/salt.service
    - target: /etc/systemd/system/salt.service
    - require:
      - file: Systemd unit
