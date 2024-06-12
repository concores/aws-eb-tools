#!/bin/sh
aws elasticbeanstalk describe-environments --query 'Environments[].[EnvironmentName]' --no-cli-pager --output text
