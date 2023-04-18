ec2Server
===

# ansible-playbook
1. ansible-playbook -i hosts.yml ansible/init.mainServer.yml -e msi=...
2. ansible-playbook -i hosts.yml ansible/config.mainServer.yml [-t ec2str] -e '{"ec2Store_passwd": ""}'
    + ansible -i hosts.yml alireza.me -m shell -a "cat /ec2str/ts.txt"
3. ansible-playbook -i hosts.yml ansible/config.mainServer.yml -t run
    + ansible -i hosts.yml alireza.me -m shell -a "netstat -nltup" 
4. ansible-playbook -i hosts.yml ansible/dns.yml -e '{"ip6": ""}'

# ansible
1. ansible -i hosts.yml alireza.me -m shell -a "echo '* * * * * date >/ec2str/ts.txt' | crontab -"
2. ansible -i hosts.yml alireza.me -m shell -a "uname -a" > msi.version
+ ansible -i hosts.yml alireza.me -m shell -a "cd /ec2str/tomcat8 && nohup bin/catalina.sh start"
+ ansible -i hosts.yml alireza.me -m shell -a "named -u named -c /ec2str/named/named.conf"

# AWS credentials
```bash
$ export AWS_ACCESS_KEY_ID="..."; export AWS_SECRET_ACCESS_KEY="..."
```
