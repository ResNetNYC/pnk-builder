base:
  'os:Raspbian':
    - match: grain
    - mysql
    - php
    - apache 
    - wordpress
  'os:Ubuntu':
    - match: grain
    - rise
