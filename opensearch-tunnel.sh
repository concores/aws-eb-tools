#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_PORT="${OS_TUNNEL_LOCAL_PORT:-10800}"

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

# ── AWS アカウント ID の取得 ─────────────────────────────────────────────────

echo "AWS アカウント ID を取得中..." >&2
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || {
    echo "エラー: AWS アカウント ID の取得に失敗しました。認証情報を確認してください。" >&2
    exit 1
}
echo "アカウント: $ACCOUNT_ID  |  プロファイル: $AWS_VAULT" >&2

# ── OpenSearch ドメイン一覧の取得 ────────────────────────────────────────────

echo "OpenSearch ドメインを取得中..." >&2

DOMAIN_NAMES=$(aws opensearch list-domain-names \
    --query 'DomainNames[].DomainName' \
    --output text 2>/dev/null) || {
    echo "エラー: OpenSearch ドメイン一覧の取得に失敗しました。" >&2
    exit 1
}

if [[ -z "$DOMAIN_NAMES" ]]; then
    echo "エラー: OpenSearch ドメインが見つかりません。" >&2
    exit 1
fi

# ── 各ドメインの詳細情報を取得（VPC エンドポイントのみ対象）─────────────────

ENTRIES=()
while IFS= read -r domain_name; do
    [[ -z "$domain_name" ]] && continue

    detail=$(aws opensearch describe-domain --domain-name "$domain_name" --output json 2>/dev/null) || continue

    # VPC エンドポイントは Endpoints.vpc またはシングル AZ の場合 Endpoint に格納される
    vpc_endpoint=$(echo "$detail" | jq -r '.DomainStatus.Endpoints.vpc // .DomainStatus.Endpoint // empty')
    vpc_id=$(echo "$detail" | jq -r '.DomainStatus.VPCOptions.VPCId // empty')
    engine_version=$(echo "$detail" | jq -r '.DomainStatus.EngineVersion // "OpenSearch"')

    # VPC エンドポイントを持たないドメイン（公開アクセス）はスキップ
    [[ -z "$vpc_endpoint" || -z "$vpc_id" ]] && continue

    ENTRIES+=("${domain_name}"$'\t'"${vpc_endpoint}"$'\t'"${vpc_id}"$'\t'"${engine_version}")
done <<< "$(echo "$DOMAIN_NAMES" | tr '\t' '\n')"

if [[ ${#ENTRIES[@]} -eq 0 ]]; then
    echo "エラー: VPC 内の OpenSearch ドメインが見つかりません。" >&2
    exit 1
fi

# ── fzf によるドメイン選択 ───────────────────────────────────────────────────

SELECTED=$(
    awk -F'\t' '{printf "%d\t%-40s  %-22s  %s\n", NR-1, $1, $4, $3}' \
        <(printf '%s\n' "${ENTRIES[@]}") |
    fzf --delimiter=$'\t' \
        --with-nth=2 \
        --exact \
        --prompt="OpenSearch ドメイン ($AWS_VAULT) > " \
        --header="ドメイン名                                エンジン                VPC" \
        --height=40% \
        --reverse
) || { echo "キャンセルしました。" >&2; exit 0; }

IDX=$(printf '%s' "$SELECTED" | cut -f1)
ENTRY="${ENTRIES[$IDX]}"

IFS=$'\t' read -r DOMAIN_NAME VPC_ENDPOINT VPC_ID ENGINE_VERSION <<< "$ENTRY"

# ── VPC 内の SSM 対応インスタンスを検索 ──────────────────────────────────────

echo "" >&2
echo "VPC ($VPC_ID) 内の SSM 対応インスタンスを検索中..." >&2

# VPC 内の実行中インスタンスをインスタンス ID と Name タグで取得
mapfile -t VPC_INSTANCES < <(aws ec2 describe-instances \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].[InstanceId, Tags[?Key==`Name`].Value|[0]]' \
    --output text)

if [[ ${#VPC_INSTANCES[@]} -eq 0 ]]; then
    echo "エラー: VPC $VPC_ID 内に実行中のインスタンスが見つかりません。" >&2
    exit 1
fi

# インスタンス ID をカンマ区切りに変換して SSM に問い合わせ
INSTANCE_IDS_CSV=$(printf '%s\n' "${VPC_INSTANCES[@]}" | cut -f1 | paste -sd ',')

SSM_ONLINE=$(aws ssm describe-instance-information \
    --filters "Key=InstanceIds,Values=$INSTANCE_IDS_CSV" \
    --query 'InstanceInformationList[?PingStatus==`Online`].InstanceId' \
    --output text 2>/dev/null | tr '\t' '\n')

if [[ -z "$SSM_ONLINE" ]]; then
    echo "エラー: VPC $VPC_ID 内に SSM 対応インスタンスが見つかりません。" >&2
    echo "SSM Agent が実行中で、適切な IAM 権限があることを確認してください。" >&2
    exit 1
fi

# SSM オンラインのインスタンスのみをターゲット候補に追加
SSM_TARGETS=()
for instance_line in "${VPC_INSTANCES[@]}"; do
    instance_id=$(echo "$instance_line" | cut -f1)
    instance_name=$(echo "$instance_line" | cut -f2)
    [[ -z "$instance_id" ]] && continue
    [[ "$instance_name" == "None" ]] && instance_name="（名前なし）"

    if echo "$SSM_ONLINE" | grep -qxF "$instance_id"; then
        SSM_TARGETS+=("${instance_id}"$'\t'"${instance_name}")
    fi
done

if [[ ${#SSM_TARGETS[@]} -eq 0 ]]; then
    echo "エラー: VPC $VPC_ID 内に SSM 対応インスタンスが見つかりません。" >&2
    exit 1
fi

# ── SSM ターゲットの選択（複数ある場合は fzf で選択）────────────────────────

if [[ ${#SSM_TARGETS[@]} -eq 1 ]]; then
    TARGET_ENTRY="${SSM_TARGETS[0]}"
else
    TARGET_SELECTED=$(
        awk -F'\t' '{printf "%d\t%-35s  %s\n", NR-1, $2, $1}' \
            <(printf '%s\n' "${SSM_TARGETS[@]}") |
        fzf --delimiter=$'\t' \
            --with-nth=2 \
            --exact \
            --prompt="SSM ターゲットインスタンス > " \
            --height=40% \
            --reverse
    ) || { echo "キャンセルしました。" >&2; exit 0; }

    TARGET_IDX=$(printf '%s' "$TARGET_SELECTED" | cut -f1)
    TARGET_ENTRY="${SSM_TARGETS[$TARGET_IDX]}"
fi

IFS=$'\t' read -r TARGET INSTANCE_NAME <<< "$TARGET_ENTRY"

# ── リージョンの抽出（エンドポイント例: vpc-xxx.ap-northeast-1.es.amazonaws.com）

REGION=$(echo "$VPC_ENDPOINT" | awk -F'.' '{print $2}')

# SSM トンネルは LOCAL_PORT+1 で受け、プロキシが LOCAL_PORT に公開する
TUNNEL_PORT=$((LOCAL_PORT + 1))

# ── 接続情報の表示 ───────────────────────────────────────────────────────────

echo "" >&2
printf "  ドメイン:       %s (%s)\n" "$DOMAIN_NAME" "$ENGINE_VERSION" >&2
printf "  エンドポイント: %s\n" "$VPC_ENDPOINT" >&2
printf "  インスタンス:   %s (%s)\n" "$TARGET" "$INSTANCE_NAME" >&2
printf "  ダッシュボード: http://localhost:%s/_dashboards\n" "$LOCAL_PORT" >&2
printf "  ※ Ctrl+C でトンネルとプロキシを終了します。\n" >&2
echo "" >&2

# ── バックグラウンドで SSM ポートフォワーディングを開始 ───────────────────────

aws ssm start-session \
    --target "$TARGET" \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "{\"host\":[\"$VPC_ENDPOINT\"],\"portNumber\":[\"443\"],\"localPortNumber\":[\"$TUNNEL_PORT\"]}" &
SSM_PID=$!

cleanup() {
    echo "" >&2
    echo "トンネルを閉じています..." >&2
    kill "$SSM_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# SSM トンネルの確立を待機
echo "SSM トンネルの確立を待機中..." >&2
for _ in $(seq 1 15); do
    (echo > /dev/tcp/127.0.0.1/"$TUNNEL_PORT") 2>/dev/null && break
    sleep 1
done

# ── SigV4 署名プロキシを起動（botocore で署名し SSM トンネルへ転送）────────────

python3 - "$LOCAL_PORT" "$TUNNEL_PORT" "$VPC_ENDPOINT" "$REGION" <<'PYEOF'
import sys, re
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import urllib3
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from botocore.session import Session as BotocoreSession

LISTEN_PORT = int(sys.argv[1])
TUNNEL_PORT  = int(sys.argv[2])
OS_HOST      = sys.argv[3]
REGION       = sys.argv[4]

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
pool = urllib3.HTTPSConnectionPool(
    '127.0.0.1', port=TUNNEL_PORT,
    cert_reqs='CERT_NONE', assert_hostname=False,
    maxsize=20,
)
credentials = BotocoreSession().get_credentials()

SKIP_HEADERS = {
    'transfer-encoding', 'connection',
    'content-security-policy', 'content-security-policy-report-only',
    'x-frame-options',
}

def sanitize_cookie(value):
    # ブラウザが HTTP localhost でクッキーを受け入れるよう属性を調整する
    value = re.sub(r';\s*Secure', '', value, flags=re.IGNORECASE)
    value = re.sub(r';\s*Domain=[^;]+', '', value, flags=re.IGNORECASE)
    value = re.sub(r'SameSite=None', 'SameSite=Lax', value, flags=re.IGNORECASE)
    return value

class ProxyHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def proxy(self):
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length) if length else None

        aws_req = AWSRequest(
            method=self.command,
            url=f"https://{OS_HOST}{self.path}",
            data=body,
        )
        SigV4Auth(credentials, 'es', REGION).add_auth(aws_req)

        headers = dict(aws_req.headers)
        headers['Host'] = OS_HOST
        headers['osd-xsrf'] = 'true'

        resp = pool.urlopen(
            self.command, self.path,
            headers=headers, body=body,
            redirect=False, preload_content=False, decode_content=False,
        )

        self.send_response(resp.status)
        for k, v in resp.headers.items():
            if k.lower() not in SKIP_HEADERS:
                if k.lower() == 'set-cookie':
                    self.send_header(k, sanitize_cookie(v))
                else:
                    self.send_header(k, v)
        self.end_headers()

        while chunk := resp.read(65536):
            self.wfile.write(chunk)
        resp.release_conn()

    do_GET = do_POST = do_PUT = do_DELETE = do_HEAD = do_OPTIONS = do_PATCH = proxy

print(f"プロキシ起動: http://localhost:{LISTEN_PORT}/_dashboards", flush=True)
ThreadingHTTPServer(('127.0.0.1', LISTEN_PORT), ProxyHandler).serve_forever()
PYEOF
