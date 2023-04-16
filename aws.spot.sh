#! /bin/bash

aws --profile at --region us-east-1 --output json ec2 request-spot-instances \
    --spot-price "0.01" --instance-count 1 --type "one-time" --launch-specification file://launch.spec.json
