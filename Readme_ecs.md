# ECS Login Script (login_ecs.sh)

ECSクラスタ内のコンテナに直接シェル接続するためのインタラクティブなスクリプトです。

## 概要

このスクリプトは以下の手順でECSコンテナへの接続を自動化します：
1. ECSクラスタの選択
2. サービスの選択
3. タスクの選択（起動時間表示付き）
4. コンテナの選択
5. `aws ecs execute-command`でシェル接続

## 前提条件

### 必要なツール
- **AWS CLI**: 設定済みで適切な権限を持つこと
- **fzf**: インタラクティブな選択のため
- **bash**: スクリプト実行環境

### 必要な権限
- `ecs:ListClusters`
- `ecs:ListServices`
- `ecs:ListTasks`
- `ecs:DescribeTasks`
- `ecs:DescribeClusters`
- `ecs:DescribeServices`
- `ecs:ExecuteCommand`

## インストール

### fzfのインストール
```bash
# macOS
brew install fzf

# Ubuntu/Debian
sudo apt install fzf

# CentOS/RHEL
sudo yum install fzf
```

## 使用方法

### 基本的な使用方法
```bash
# 全てインタラクティブに選択
./login_ecs.sh

# ヘルプ表示
./login_ecs.sh -h
./login_ecs.sh --help
```

### パラメータ指定での使用方法
```bash
# クラスタのみ指定
./login_ecs.sh my-cluster

# クラスタとサービスを指定
./login_ecs.sh my-cluster my-service

# 全てのパラメータを指定
./login_ecs.sh my-cluster my-service my-container
```

### パラメータ
| 位置 | パラメータ | 説明 | 必須 |
|------|-----------|------|------|
| 1    | cluster   | ECSクラスタ名 | いいえ |
| 2    | service   | ECSサービス名 | いいえ |
| 3    | container | コンテナ名 | いいえ |

## 機能

### 自動選択機能
- **選択肢が1つの場合**: 自動的に選択して次のステップに進む
- **複数の選択肢がある場合**: fzfでインタラクティブに選択

### タスク表示機能
- タスクARNと起動時間を表示
- 表示形式: `タスクARN (Started: YYYY-MM-DD HH:MM:SS)`
- macOSとLinux両対応の時刻フォーマット

### エラーハンドリング
- 指定されたリソースの存在確認
- 適切なエラーメッセージの表示
- 各ステップでの検証

## 使用例

### 例1: 全てインタラクティブに選択
```bash
$ ./login_ecs.sh
Select a cluster: my-production-cluster
Selected cluster: my-production-cluster
Select a service: web-service
Selected service: web-service
Select a task:
  arn:aws:ecs:us-west-2:123456789012:task/my-cluster/abc123 (Started: 2024-01-15 10:30:45)
  arn:aws:ecs:us-west-2:123456789012:task/my-cluster/def456 (Started: 2024-01-15 09:15:22)
Selected task: arn:aws:ecs:us-west-2:123456789012:task/my-cluster/abc123
Select a container: app
Selected container: app
```

### 例2: パラメータ指定
```bash
$ ./login_ecs.sh my-cluster web-service app
Using specified cluster: my-cluster
Using specified service: web-service
Selected task: arn:aws:ecs:us-west-2:123456789012:task/my-cluster/abc123
Using specified container: app
```

## トラブルシューティング

### よくあるエラー

#### fzfが見つからない
```
fzf could not be found, please install fzf first.
```
**解決方法**: fzfをインストールしてください

#### クラスタが見つからない
```
Error: Cluster 'my-cluster' not found.
```
**解決方法**: 正しいクラスタ名を指定するか、AWS CLIの設定を確認してください

#### 権限不足
```
An error occurred (AccessDeniedException) when calling the ExecuteCommand operation
```
**解決方法**: 必要なIAM権限が付与されていることを確認してください

### デバッグ
スクリプトの動作を詳しく確認したい場合は、デバッグモードで実行できます：
```bash
bash -x ./login_ecs.sh
```

## 注意事項

- ECSタスクでExecute Commandを使用するには、タスク定義で`enableExecuteCommand`が有効になっている必要があります
- コンテナにはシェル（`/bin/sh`または`/bin/bash`）が利用可能である必要があります
- ネットワーク設定によってはVPCエンドポイントの設定が必要な場合があります
