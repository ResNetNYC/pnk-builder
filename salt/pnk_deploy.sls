# -*- coding: utf-8 -*-
# vim: ft=sls

Unifi service:
  service.running:
    - name: unifi
    - enable: True
    - require:
      - pkg: Unifi package
