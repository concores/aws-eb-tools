#!/usr/bin/env bash

ENVIRONMENTS=(
    "photoruction-php82-alpha"
    "photoruction-php82-beta"
    "photoruction-php82-gamma"
)

show_usage() {
    echo "Usage: $0 [eb_env_or_cycle]"
    echo "  eb_env_or_cycle: EB環境名 または CycleEnvタグの値（例: red, green, blue）"
    echo "                   省略した場合は、一覧から選択するプロンプトが表示されます。"
}

EB_ENV_PARAM="$1"

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_usage
    exit 0
fi

if [ -n "$EB_ENV_PARAM" ]; then
    # CycleEnv タグで環境を検索
    RESOLVED_ENV=""
    for env in "${ENVIRONMENTS[@]}"; do
        ENV_ARN=$(aws elasticbeanstalk describe-environments \
            --environment-names "$env" \
            --query 'Environments[0].EnvironmentArn' \
            --output text 2>/dev/null)

        if [ -z "$ENV_ARN" ] || [ "$ENV_ARN" = "None" ]; then
            continue
        fi

        CYCLE_ENV_TAG=$(aws elasticbeanstalk list-tags-for-resource \
            --resource-arn "$ENV_ARN" \
            --query 'ResourceTags[?Key==`CycleEnv`].Value' \
            --output text 2>/dev/null)

        if [[ "${CYCLE_ENV_TAG,,}" == "${EB_ENV_PARAM,,}" ]]; then
            RESOLVED_ENV="$env"
            break
        fi
    done

    if [ -n "$RESOLVED_ENV" ]; then
        EB_ENV="$RESOLVED_ENV"
        echo "CycleEnv '${EB_ENV_PARAM}' -> EB env: ${EB_ENV}"
    else
        EB_ENV="$EB_ENV_PARAM"
        echo "Using specified EB env: ${EB_ENV}"
    fi
else
    EB_ENV=$(./01_get_eb_envs.sh | fzf)
    echo "EB env: ${EB_ENV}"
fi

EB_INSTANCE=$(./02_get_instances.sh ${EB_ENV} | fzf)
echo "EB instance: ${EB_INSTANCE}"
./03_connect_to_instance.sh ${EB_INSTANCE}
