# AWS ElasticBeanstalkクエリツールキット

## 前提条件

1. `aws-vault` のインストールと設定完了
2. `Session Managerプラグイン` のインストール [詳細](https://docs.aws.amazon.com/ja_jp/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
3. `aws-vault` 環境内で実行

## コマンド

### get_eb_envs.sh

EB環境を調べて、出力する。

呼び出し方：

```
$ ./get_eb_envs.sh
```

引数：なし

### get_instances.sh

対象EB環境のインスタンスIDを取得する。

呼び出し方：

```
$ ./get_instances.sh <EB_ENV_NAME>
```

引数：

- EB_ENV_NAME: EB環境名（ `get_eb_envs.sh` で取得可能）

### connect_to_instance.sh

対象インスタンスにSSH（AWS SSMを利用して）で接続する。

呼び出し方：

```
$ ./connect_to_instance.sh <INSTANCE_ID>
```

引数：

- INSTANCE_ID: インスタンスID（ `get_instances.sh` で取得可能）
