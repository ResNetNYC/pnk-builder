wordpress:
  cli:
    source: https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    hash:  https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar.sha512
    allowroot: False
  sites:
    pnk.local:
      username: wordpress
      password: wordpress
      database: wordpress
      dbhost: localhost
      dbuser: wordpress
      dbpass: wordpress
      url: http://pnk.local
      title: 'PNK'
      email: contact@pnkgo.com
  lookup:
    docroot: /var/www/html

mysql:
  server:
    mysql:
      bind-address: 127.0.0.1
  database:
    - wordpress
  user:
    wordpress:
      password: 'wordpress'
      host: localhost
      databases:
        - database: wordpress
          grants: ['all privileges']

apache:
  sites:
    pnk.local:
      enabled: True
      template_file: salt://apache/vhosts/standard.tmpl
      DocumentRoot: /var/www/html
