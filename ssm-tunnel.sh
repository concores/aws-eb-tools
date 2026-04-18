#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SSM_TUNNEL_CONFIG:-${SCRIPT_DIR}/tunnels.conf}"

# ── 依存コマンドの確認 ───────────────────────────────────────────────────────

for cmd in aws fzf jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "エラー: '$cmd' がインストールされていません。" >&2
        exit 1
    fi
done

# ── AWS 認証情報の確認 ───────────────────────────────────────────────────────
# aws-vault exec により AWS_VAULT が設定されていることを前提とします。

if [[ -z "${AWS_VAULT:-}" ]]; then
    echo "エラー: aws-vault セッションが検出されません。" >&2
    echo "" >&2
    echo "aws-vault セッション内でスクリプトを実行してください。例:" >&2
    echo "  aws-vault exec <プロファイル名> -- $0" >&2
    exit 1
fi

# ── 設定ファイルの確認 ───────────────────────────────────────────────────────

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "エラー: 設定ファイルが見つかりません: $CONFIG_FILE" >&2
    echo "ヒント: SSM_TUNNEL_CONFIG 環境変数でパスを上書きできます。" >&2
    exit 1
fi

# ── AWS アカウント ID の取得 ─────────────────────────────────────────────────

echo "AWS アカウント ID を取得中..." >&2
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || {
    echo "エラー: AWS アカウント ID の取得に失敗しました。認証情報を確認してください。" >&2
    exit 1
}
echo "アカウント: $ACCOUNT_ID  |  プロファイル: $AWS_VAULT" >&2

# ── 現在のアカウントに対応するトンネル定義を抽出 ─────────────────────────────
# TSV 形式で出力: name\ttarget\thost\tport\tlocal_port

ENTRIES=()
while IFS= read -r line; do
    ENTRIES+=("$line")
done < <(
    jq -r --arg account "$ACCOUNT_ID" \
        '.[] | select(.account == $account) | .tunnels[] |
         [.name, .target, .host, (.port|tostring), (.local_port|tostring)] | @tsv' \
        "$CONFIG_FILE"
)

if [[ ${#ENTRIES[@]} -eq 0 ]]; then
    echo "エラー: アカウント $ACCOUNT_ID に対応するトンネル定義が $CONFIG_FILE に見つかりません。" >&2
    exit 1
fi

# ── fzf による接続先の選択 ───────────────────────────────────────────────────
# 先頭に配列インデックスを付加し、--with-nth でユーザーには非表示にする。

SELECTED=$(
    awk -F'\t' '{printf "%d\t%-35s  %s:%s  ->  localhost:%s\n", NR-1, $1, $3, $4, $5}' \
        <(printf '%s\n' "${ENTRIES[@]}") |
    fzf --delimiter=$'\t' \
        --with-nth=2 \
        --exact \
        --prompt="トンネル ($AWS_VAULT) > " \
        --height=40% \
        --reverse
) || { echo "キャンセルしました。" >&2; exit 0; }

IDX=$(printf '%s' "$SELECTED" | cut -f1)
ENTRY="${ENTRIES[$IDX]}"

IFS=$'\t' read -r DISPLAY_NAME TARGET HOST PORT LOCAL_PORT <<< "$ENTRY"

# ── 接続情報の表示 ───────────────────────────────────────────────────────────

echo "" >&2
printf "  接続先:         %s\n" "$DISPLAY_NAME" >&2
printf "  リモートホスト: %s:%s\n" "$HOST" "$PORT" >&2
printf "  ローカルポート: localhost:%s\n" "$LOCAL_PORT" >&2
printf "  インスタンス:   %s\n" "$TARGET" >&2
echo "" >&2

# ── SSM ポートフォワーディングセッションの開始 ───────────────────────────────

exec aws ssm start-session \
    --target "$TARGET" \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "{\"host\":[\"$HOST\"],\"portNumber\":[\"$PORT\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}"
