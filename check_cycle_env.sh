#!/bin/bash

# 対象のElastic Beanstalk環境名を配列で定義
ENVIRONMENTS=(
    "photoruction-php82-alpha"
    "photoruction-php82-beta"
    "photoruction-php82-gamma"
)

# 各環境のタグを確認
for env in "${ENVIRONMENTS[@]}"; do

    # まず環境の詳細情報を取得してEnvironmentIdを取得
    ERROR_OUTPUT=$(mktemp)
    ENV_INFO=$(aws elasticbeanstalk describe-environments \
        --environment-names "$env" \
        --query 'Environments[0].[EnvironmentId,EnvironmentArn]' \
        --output text 2>"$ERROR_OUTPUT")

        # 環境が存在するかチェック
    if [ $? -ne 0 ] || [ -z "$ENV_INFO" ] || [ "$ENV_INFO" = "None	None" ]; then
        rm -f "$ERROR_OUTPUT"
        echo "$env: 環境が見つかりません"
        continue
    fi

    # 環境ARNを抽出（2番目のフィールド）
    ENV_ARN=$(echo "$ENV_INFO" | cut -f2)

    # 環境のタグを取得
    CYCLE_ENV_TAG=$(aws elasticbeanstalk list-tags-for-resource \
        --resource-arn "$ENV_ARN" \
        --query 'ResourceTags[?Key==`CycleEnv`].Value' \
        --output text 2>"$ERROR_OUTPUT")

    # タグ取得のエラーハンドリング
    if [ $? -ne 0 ]; then
        rm -f "$ERROR_OUTPUT"
        echo "$env: タグ取得エラー"
        continue
    fi

    # 一時ファイルを削除
    rm -f "$ERROR_OUTPUT"

    # タグの値を表示
    if [ -z "$CYCLE_ENV_TAG" ]; then
        echo "$env: CycleEnvタグなし"
    else
        echo "$env: $CYCLE_ENV_TAG"
    fi
done
