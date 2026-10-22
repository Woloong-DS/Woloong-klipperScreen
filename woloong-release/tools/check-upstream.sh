#!/bin/bash
# ============================================================================
# check-upstream.sh —— 审计「我们的发行树」与「上游发布」的对应关系
#   判定：woloong-release/upstream.json 里的 base_ref 是否等于上游最新 tag
#   若落后：**逐一列出所有未吸收的上游版本**（不遗漏任何一个），退出码 1
# 说明：最新版本直接取 **上游远端** 的 tag（ls-remote），不用本地 tag —
#       本地同名 tag 已被我们的发行提交重指，按 creatordate 排序会误判。
# 用法: bash woloong-release/tools/check-upstream.sh
# ============================================================================
set -u
cd "$(dirname "$0")/.." || exit 1        # → woloong-release/
root="$(cd .. && pwd)"
J="upstream.json"
[ -f "$J" ] || { echo "[FAIL] 缺少 $J（基线声明）"; exit 2; }

json_val() {
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$J" | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//'
}
REPO=$(json_val repo)
BASE=$(json_val base_ref)
BASESHA=$(json_val base_sha)
[ -n "$REPO" ] && [ -n "$BASE" ] || { echo "[FAIL] $J 缺少 repo/base_ref"; exit 2; }

git -C "$root" remote get-url upstream >/dev/null 2>&1 || git -C "$root" remote add upstream "https://github.com/$REPO.git"
git -C "$root" fetch -q --tags --force upstream || { echo "[FAIL] 无法抓取上游 $REPO"; exit 2; }

# 只认 vX.Y.Z 形式的上游发布 tag，按版本号排序（-V），最后一个即最新
TAGS=$(git -C "$root" ls-remote --tags --refs upstream 2>/dev/null \
  | sed 's#.*refs/tags/##' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V)
LATEST=$(printf '%s\n' "$TAGS" | tail -1)

echo "上游仓库 : $REPO"
echo "我们的基线: $BASE  ($BASESHA)"
echo "上游最新  : $LATEST"
if [ -z "$LATEST" ]; then echo '[WARN] 上游没有任何 vX.Y.Z tag（可能改用分支发布）'; exit 1; fi
if [ "$BASE" = "$LATEST" ]; then
  echo '[OK] 我们的发行树已对应上游最新发布 ✓'
  exit 0
fi

MISSED=$(printf '%s\n' "$TAGS" | awk -v base="$BASE" 'f{print} $0==base{f=1}')
N=$(printf '%s\n' "$MISSED" | grep -c . || true)
echo "[BEHIND] 落后上游，未吸收的版本共 $N 个（逐一列出，确保不遗漏）:"
printf '%s\n' "$MISSED" | sed 's/^/  - /'
echo "处理：跑 upstream-sync 工作流（或本地 fork-sync）吸收到 $LATEST"
exit 1
