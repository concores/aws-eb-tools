#!/bin/bash

# 使用方法の表示
show_usage() {
    echo "Usage: $0 [cluster] [service] [container]"
    echo "  cluster:   ECS cluster name (optional)"
    echo "  service:   ECS service name (optional)"
    echo "  container: Container name (optional)"
    echo ""
    echo "All parameters are optional. If not provided, you'll be prompted to select from available options."
}

# パラメータの取得
CLUSTER_PARAM="$1"
SERVICE_PARAM="$2"
CONTAINER_PARAM="$3"

# ヘルプオプション
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_usage
    exit 0
fi

# fzfがインストールされているか確認
if ! command -v fzf &> /dev/null; then
    echo "fzf could not be found, please install fzf first."
    exit 1
fi

# Step 1: ECSクラスタの選択
if [ -n "$CLUSTER_PARAM" ]; then
    # パラメータで指定された場合
    selected_cluster="$CLUSTER_PARAM"
    echo "Using specified cluster: $selected_cluster"

    # 指定されたクラスタが存在するか確認
    if ! aws ecs describe-clusters --clusters "$selected_cluster" --query "clusters[0].clusterName" --output text &>/dev/null; then
        echo "Error: Cluster '$selected_cluster' not found."
        exit 1
    fi
else
    # パラメータで指定されていない場合は一覧から選択
    clusters=$(aws ecs list-clusters --query "clusterArns[]" --output text)

    if [ -z "$clusters" ]; then
        echo "No clusters found."
        exit 1
    fi

    # クラスタ一覧を表示して選択 (fzf)
    selected_cluster=$(echo "$clusters" | xargs -n1 | fzf --select-1 --prompt="Select a cluster: ")

    if [ -z "$selected_cluster" ]; then
        echo "No cluster selected."
        exit 1
    fi
    echo "Selected cluster: $selected_cluster"
fi

# Step 2: ECSサービスの選択
if [ -n "$SERVICE_PARAM" ]; then
    # パラメータで指定された場合
    selected_service="$SERVICE_PARAM"
    echo "Using specified service: $selected_service"

    # 指定されたサービスが存在するか確認
    service_check=$(aws ecs describe-services --cluster "$selected_cluster" --services "$selected_service" --query "services[0].serviceName" --output text 2>/dev/null)
    if [ "$service_check" == "None" ] || [ -z "$service_check" ]; then
        echo "Error: Service '$selected_service' not found in cluster '$selected_cluster'."
        exit 1
    fi
else
    # パラメータで指定されていない場合は一覧から選択
    services=$(aws ecs list-services --cluster "$selected_cluster" --query "serviceArns[]" --output text)

    if [ -z "$services" ];then
        echo "No services found in the selected cluster."
        exit 1
    fi

    # サービス一覧を表示して選択 (fzf)
    selected_service=$(echo "$services" | xargs -n1 | fzf --select-1 --prompt="Select a service: ")

    if [ -z "$selected_service" ]; then
        echo "No service selected."
        exit 1
    fi
    echo "Selected service: $selected_service"
fi

# Step 3: サービスに紐づくタスク一覧の取得
tasks=$(aws ecs list-tasks --cluster "$selected_cluster" --service-name "$selected_service" --query "taskArns[]" --output text)

if [ -z "$tasks" ]; then
    echo "No tasks found in the selected service."
    exit 1
fi

# タスクが1つかどうかを確認
task_count=$(echo "$tasks" | wc -w)

if [ "$task_count" -eq 1 ]; then
    # タスクが1つの場合は自動選択
    selected_task="$tasks"
    # echo "Only one task found, auto-selecting: $selected_task"
else
    # 複数のタスクがある場合は詳細情報を取得して選択
    task_details=""
    for task_arn in $tasks; do
        created_at=$(aws ecs describe-tasks --cluster "$selected_cluster" --tasks "$task_arn" --query "tasks[0].createdAt" --output text)

        # ISO 8601形式の日時をより読みやすい形式に変換
        if command -v date &> /dev/null; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                # macOS
                formatted_time=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${created_at%.*}" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$created_at")
            else
                # Linux
                formatted_time=$(date -d "$created_at" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "$created_at")
            fi
        else
            formatted_time="$created_at"
        fi

        task_details="${task_details}${task_arn} (Started: ${formatted_time})\n"
    done

    # タスク一覧を表示して選択 (fzf)
    selected_task_line=$(echo -e "$task_details" | fzf --prompt="Select a task: ")

    if [ -z "$selected_task_line" ]; then
        echo "No task selected."
        exit 1
    fi

    # 選択された行からタスクARNを抽出
    selected_task=$(echo "$selected_task_line" | cut -d' ' -f1)
fi

echo "Selected task: $selected_task"

# Step 4: コンテナの選択
if [ -n "$CONTAINER_PARAM" ]; then
    # パラメータで指定された場合
    selected_container="$CONTAINER_PARAM"
    echo "Using specified container: $selected_container"

    # 指定されたコンテナが存在するか確認
    container_names=$(aws ecs describe-tasks --cluster "$selected_cluster" --tasks $selected_task --query "tasks[0].containers[*].name" --output text)
    if [ -z "$container_names" ]; then
        echo "Failed to get container list."
        exit 1
    fi

    if ! echo "$container_names" | grep -q "\b$selected_container\b"; then
        echo "Error: Container '$selected_container' not found in task '$selected_task'."
        echo "Available containers: $container_names"
        exit 1
    fi
else
    # パラメータで指定されていない場合は一覧から選択
    container_names=$(aws ecs describe-tasks --cluster "$selected_cluster" --tasks $selected_task --query "tasks[0].containers[*].name" --output text)
    if [ -z "$container_names" ]; then
        echo "Failed to get container."
        exit 1
    fi

    # コンテナ一覧を表示して選択 (fzf)
    selected_container=$(echo "$container_names" | xargs -n1 | fzf --select-1 --prompt="Select a container: ")

    if [ -z "$selected_container" ]; then
        echo "No container selected."
        exit 1
    fi
    echo "Selected container: $selected_container"
fi

# Step 5: execute-commandでコンテナにシェル接続
aws ecs execute-command --task "$selected_task" --interactive --cluster "$selected_cluster" --container "$selected_container" --command "/bin/sh"
