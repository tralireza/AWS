mainServer
===

# ansible-playbook
1. ansible-playbook -i hosts.yml ansible/init.mainServer.yml -e msi=...
2. ansible-playbook -i hosts.yml ansible/config.mainServer.yml -t ec2Store -e '{"ec2Store_passwd": ""}'
2.a. ansible -i hosts.yml alireza.me -m shell -a "cat /ec2str/ts.txt"
3. ansible-playbook -i hosts.yml ansible/config.mainServer.yml -t runSvcs
3.a. ansible -i hosts.yml alireza.me -m shell -a "netstat -nltup" 
4. ansible-playbook -i hosts.yml ansible/dns.yml -e '{"ip": ""}'

# ansible
1. ansible -i hosts.yml alireza.me -m shell -a "cd /ec2str/tomcat8 && nohup bin/catalina.sh start"
2. ansible -i hosts.yml alireza.me -m shell -a "named -u named -c /ec2str/named/named.conf"
3. ansible -i hosts.yml alireza.me -m shell -a "echo '* * * * * date >/ec2str/ts.txt' | crontab -"

# AWS credentials
```bash
$ export AWS_ACCESS_KEY_ID="..."; export AWS_SECRET_ACCESS_KEY="..."
```
