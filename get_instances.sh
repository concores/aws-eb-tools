#!/bin/sh
aws elasticbeanstalk describe-environment-resources --environment-name $1 --query 'EnvironmentResources.Instances[].[Id]' --no-cli-pager --output text
