#!/bin/bash

~/aws-cli/aws --profile root --region us-east-1 --output yaml ec2 request-spot-instances \
    --spot-price "0.0075" --instance-count 1 --type "one-time" --launch-specification file://launch.spec.json
