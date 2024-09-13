#!/bin/bash

# fzfがインストールされているか確認
if ! command -v fzf &> /dev/null; then
    echo "fzf could not be found, please install fzf first."
    exit 1
fi

# Step 1: ECSクラスタ一覧の取得
clusters=$(aws ecs list-clusters --query "clusterArns[]" --output text)

if [ -z "$clusters" ]; then
    echo "No clusters found."
    exit 1
fi

# クラスタ一覧を表示して選択 (fzf)
selected_cluster=$(echo "$clusters" | xargs -n1 | fzf --prompt="Select a cluster: ")

if [ -z "$selected_cluster" ]; then
    echo "No cluster selected."
    exit 1
fi
echo "Selected cluster: $selected_cluster"

# Step 2: クラスタに紐づくサービス一覧の取得
services=$(aws ecs list-services --cluster "$selected_cluster" --query "serviceArns[]" --output text)

if [ -z "$services" ];then
    echo "No services found in the selected cluster."
    exit 1
fi

# サービス一覧を表示して選択 (fzf)
selected_service=$(echo "$services" | xargs -n1 | fzf --prompt="Select a service: ")

if [ -z "$selected_service" ]; then
    echo "No service selected."
    exit 1
fi
echo "Selected service: $selected_service"

# Step 3: サービスに紐づくタスク一覧の取得
tasks=$(aws ecs list-tasks --cluster "$selected_cluster" --service-name "$selected_service" --query "taskArns[]" --output text)

if [ -z "$tasks" ]; then
    echo "No tasks found in the selected service."
    exit 1
fi

# タスク一覧を表示して選択 (fzf)
selected_task=$(echo "$tasks" | xargs -n1 | fzf --prompt="Select a task: ")

if [ -z "$selected_task" ]; then
    echo "No task selected."
    exit 1
fi
echo "Selected task: $selected_task"

# Step 4: コンテナ名の取得
container_name=$(aws ecs describe-tasks --cluster "$selected_cluster" --tasks $selected_task --query "tasks[0].containers[0].name" --output text)
if [ -z "$container_name" ]; then
    echo "Failed to get container."
    exit 1
fi

echo "Target container: $container_name"

# Step 5: execute-commandでコンテナにシェル接続
aws ecs execute-command --task "$selected_task" --interactive --cluster "$selected_cluster" --container "$container_name" --command "/bin/sh"
