# ec2Server

## ansible-playbook
1. ansible-playbook -i hosts.yml ansible/init.mainServer.yml -e msi=...
2. ansible-playbook -i hosts.yml ansible/config.mainServer.yml [-t ec2str] -e '{"ec2Store_passwd": ""}'
    + ansible -i hosts.yml alireza.me -m shell -a "cat /ec2str/ts.txt && date"
3. ansible-playbook -i hosts.yml ansible/config.mainServer.yml -t run
    + ansible -i hosts.yml alireza.me -m shell -a "netstat -nltup" 
4. ansible-playbook -i hosts.yml ansible/dns.yml -e '{"ip6": ""}'

## ansible
1. ansible -i hosts.yml alireza.me -m shell -a "cat /ec2str/crontab.l | crontab -"
    + asnible -i hosts.yml alireza.me -m shell -a "crontab -l"
2. ansible -i hosts.yml alireza.me -m shell -a "uname -a" > msi.version
+ ansible -i hosts.yml alireza.me -m shell -a "cd /ec2str/tomcat8 && nohup bin/catalina.sh start"
+ ansible -i hosts.yml alireza.me -m shell -a "named -u named -c /ec2str/named/named.conf"

## AWS credentials
```bash
$ export AWS_ACCESS_KEY_ID="..."; export AWS_SECRET_ACCESS_KEY="..."
```

## DNS-SEC
```bash
$ ansible -i hosts.yml alireza.me -m shell -a "ssh-keygen -r alireza.me"
```

## IPTables
```bash
$ ansible -i hosts.yml alireza.me -m shell -a "modprobe xt_recent ip_list_tot=2048 ip_pkt_list_tot=32"
$ ansible -i hosts.yml alireza.me -m shell -a "iptables-restore /ec2str/ipt.rules"
$ ansible -i hosts.yml alireza.me -m shell -a "ip6tables-restore /ec2str/ip6t.rules"
$ ansible -i hosts.yml alireza.me -m shell -a "cat /sys/module/xt_recent/parameters/ip_list_tot"
$ ansible -i hosts.yml alireza.me -m shell -a "cat /proc/net/xt_recent/DEFAULT"
```
