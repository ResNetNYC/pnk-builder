# -*- coding: utf-8 -*-
# vim: ft=sls

Set hostname:
  network.system:
    - enabled: True
    - hostname: pnkserver
    - apply_hostname: True
    - retain_settings: True
