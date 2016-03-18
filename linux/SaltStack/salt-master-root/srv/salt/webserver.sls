apache2:
  pkg:
    - installed

/var/www/html/index.html:
  file.managed:
    - source: salt://apache2/index.html
    - require:
      - pkg: apache2

crontab_checkhighstate:
  cron.present:
    - identifier: CHECK_HIGHSTATE
    - name: salt-call state.highstate
    - user: root
    - minute: '*/1'
    - hour: '*'
    - daymonth: '*'
    - month: '*'
    - dayweek: '*'
