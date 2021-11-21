mainServer
===

# ansible-playbook
1. ansible-playbook -i hosts.yml -vv ansible/init.mainServer.yml -e mainServer_instanceId=
2. ansible-playbook -i hosts.yml -vv ansible/config.mainServer.yml -t ec2Store -e '{"ec2Store_passwd": ""}'
3. ansible-playbook -i hosts.yml -vv ansible/config.mainServer.yml -t runSvcs

# ansible
1. ansible -i hosts.yml 54.84.117.224 -vv -m shell -a "cd /ec2Store/tomcat8 && nohup bin/catalina.sh start"
2. ansible -i hosts.yml 54.84.117.224 -vv -m shell -a "named -u named -c /ec2Store/named/named.conf"

# AWS credentials
```bash
export AWS_ACCESS_KEY_ID="..."; export AWS_SECRET_ACCESS_KEY="..."
```
