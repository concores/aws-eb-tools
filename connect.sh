#!/bin/bash
function resultCheck() {
    if [ $1 -ne 0 ]; then
        echo "ERROR!"
        exit 1
    fi
}

get_eb_env="sh ./01_get_eb_envs.sh"
get_instances="sh ./02_get_instances.sh"
connect_ssm="sh ./03_connect_to_instance.sh"

eval $get_eb_env
resultCheck $? 

echo -e "\n"
echo -n choose_eb_env? : 
read env_name
eval $get_instances $env_name;
resultCheck $? 

echo -e "\n"
echo -n choose_instance_id? : 
read instance
eval $connect_ssm $instance;
resultCheck $? 

