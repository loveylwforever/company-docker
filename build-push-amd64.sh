#!/usr/bin/env bash
# 在 Mac（含 Apple Silicon）上交叉编译 linux/amd64 自研镜像，导出离线 tar 供阿里云 ECS 加载。
#
# 用法（在 company-docker 目录）：
#   ./build-push-amd64.sh --help
#   ./build-push-amd64.sh
#   ./build-push-amd64.sh auth
#   ./build-push-amd64.sh auth admin-dashboard --no-save
#   IMAGE_TAG=amd64 NODE_HEAP_MB=3072 ./build-push-amd64.sh manage
#
# 本地验证架构：
#   docker image inspect company-auth:amd64 --format '{{.Architecture}}'
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose-amd64.yml"
OUTPUT_DIR="${OUTPUT_DIR:-$SCRIPT_DIR/dist}"
IMAGE_TAG="${IMAGE_TAG:-amd64}"
NODE_HEAP_MB="${NODE_HEAP_MB:-2048}"
PLATFORM="${PLATFORM:-linux/amd64}"
SAVE_TAR=1

ALL_SERVICES=(auth auth-channel manage admin-dashboard)

image_for_service() {
  case "$1" in
    auth) echo "company-auth:${IMAGE_TAG}" ;;
    auth-channel) echo "company-auth-channel:${IMAGE_TAG}" ;;
    manage) echo "company-manage:${IMAGE_TAG}" ;;
    admin-dashboard) echo "admin-dashboard:${IMAGE_TAG}" ;;
    *)
      echo "未知服务: $1" >&2
      return 1
      ;;
  esac
}

usage() {
  cat <<EOF
build-push-amd64.sh — 在 macOS（含 Apple Silicon）交叉构建 linux/amd64 自研镜像并导出离线 tar

用法:
  $(basename "$0") [选项] [服务名...]

说明:
  在 company-docker 目录执行。不指定服务名时构建全部 4 个自研服务；
  指定一个或多个服务名时仅构建所选服务，适合日常只更新某一个服务。

选项:
  -h, --help      显示本帮助并退出
  --no-save       仅 docker compose build，不执行 docker save 打包 tar

可选服务名（compose 服务名）:
  auth              company-auth:${IMAGE_TAG}
  auth-channel      company-auth-channel:${IMAGE_TAG}
  manage            company-manage:${IMAGE_TAG}
  admin-dashboard   admin-dashboard:${IMAGE_TAG}

环境变量:
  IMAGE_TAG=${IMAGE_TAG}
                    镜像标签；默认 amd64，与本机开发用的 :local 区分
  NODE_HEAP_MB=${NODE_HEAP_MB}
                    admin-dashboard 构建时 Node 堆内存上限（MB）
  OUTPUT_DIR=${OUTPUT_DIR}
                    离线 tar 输出目录
  PLATFORM=${PLATFORM}
                    Docker 构建目标平台

示例:
  # 构建全部 4 个服务并打包
  $(basename "$0")

  # 只更新 auth 服务（构建 + 导出单服务 tar）
  $(basename "$0") auth

  # 只更新管理台，加大构建内存
  NODE_HEAP_MB=3072 $(basename "$0") admin-dashboard

  # 本地试构建，不打包
  $(basename "$0") manage --no-save

  # 同时构建两个服务
  $(basename "$0") auth auth-channel

  # 验证镜像架构
  docker image inspect company-auth:${IMAGE_TAG} --format '{{.Architecture}}'

产出:
  全量 tar:
    ${OUTPUT_DIR}/company-images-${IMAGE_TAG}-<时间戳>.tar
    ${OUTPUT_DIR}/company-images-${IMAGE_TAG}-latest.tar  (软链指向最新)

  单/多服务 tar（文件名含服务名）:
    ${OUTPUT_DIR}/company-images-auth-${IMAGE_TAG}-<时间戳>.tar
    ${OUTPUT_DIR}/company-images-auth-manage-${IMAGE_TAG}-latest.tar

  tar 内仅含自研镜像，不含 postgres / redis / artemis（ECS 首次 up 时从 Hub 拉取）。

阿里云 ECS 部署（全量）:
  scp ${OUTPUT_DIR}/company-images-${IMAGE_TAG}-latest.tar user@<ecs>:/opt/company-docker/dist/
  ssh user@<ecs>
  cd /opt/company-docker
  docker load -i dist/company-images-${IMAGE_TAG}-latest.tar
  docker compose -f docker-compose-amd64.yml up -d

阿里云 ECS 部署（仅更新某一服务，示例 auth）:
  scp ${OUTPUT_DIR}/company-images-auth-${IMAGE_TAG}-latest.tar user@<ecs>:/opt/company-docker/dist/
  ssh user@<ecs> 'cd /opt/company-docker && docker load -i dist/company-images-auth-${IMAGE_TAG}-latest.tar'
  ssh user@<ecs> 'cd /opt/company-docker && docker compose -f docker-compose-amd64.yml up -d auth'

注意:
  - 需在 company-parent 仓库结构完整时执行（构建上下文为上级目录）
  - 使用 docker-compose-amd64.yml，镜像标签为 :${IMAGE_TAG}
  - 生产环境请修改 .env 中的 POSTGRES_PASSWORD、REDIS_PASSWORD、MQ_PASSWORD 等
EOF
}

SELECTED_SERVICES=()

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
    --no-save)
      SAVE_TAR=0
      ;;
    auth|auth-channel|manage|admin-dashboard)
      SELECTED_SERVICES+=("$arg")
      ;;
    *)
      echo "未知参数: $arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ${#SELECTED_SERVICES[@]} -eq 0 ]]; then
  SELECTED_SERVICES=("${ALL_SERVICES[@]}")
else
  # 去重并保持顺序（兼容 bash 3.2；空数组在 set -u 下不可直接 "${arr[@]}" 展开）
  UNIQUE_SERVICES=()
  for svc in "${SELECTED_SERVICES[@]}"; do
    seen=0
    if ((${#UNIQUE_SERVICES[@]} > 0)); then
      for existing in "${UNIQUE_SERVICES[@]}"; do
        if [[ "$existing" == "$svc" ]]; then
          seen=1
          break
        fi
      done
    fi
    if [[ "$seen" -eq 0 ]]; then
      UNIQUE_SERVICES+=("$svc")
    fi
  done
  SELECTED_SERVICES=("${UNIQUE_SERVICES[@]}")
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "错误: 未找到 docker 命令" >&2
  exit 1
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "错误: 未找到 $COMPOSE_FILE" >&2
  exit 1
fi

if [[ ! -f "$ROOT_DIR/pom.xml" ]]; then
  echo "错误: 构建上下文应为 company-parent 根目录，未找到 $ROOT_DIR/pom.xml" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

APP_IMAGES=()
for svc in "${SELECTED_SERVICES[@]}"; do
  APP_IMAGES+=("$(image_for_service "$svc")")
done

SERVICE_LIST="$(printf '%s ' "${SELECTED_SERVICES[@]}")"

echo "==> 目标平台: $PLATFORM"
echo "==> 镜像标签: $IMAGE_TAG"
echo "==> NODE_HEAP_MB: $NODE_HEAP_MB"
echo "==> compose: $COMPOSE_FILE"
echo "==> 构建服务: ${SERVICE_LIST%/}"

export DOCKER_DEFAULT_PLATFORM="$PLATFORM"
export IMAGE_TAG
export NODE_HEAP_MB

cd "$SCRIPT_DIR"

# Java 服务基础镜像（始终预拉）
JAVA_BASE_IMAGES=(
  "maven:3.9-eclipse-temurin-21-alpine"
  "eclipse-temurin:21-jre-alpine"
)
echo "==> 预拉取 Java 基础镜像..."
for base in "${JAVA_BASE_IMAGES[@]}"; do
  echo "    pull $base ($PLATFORM) ..."
  if ! docker pull --platform="$PLATFORM" "$base"; then
    echo "警告: 预拉取 $base 失败，build 将继续尝试" >&2
  fi
done

# admin-dashboard：运行层 distroless；构建阶段 bookworm-slim（无 node:22-alpine）
needs_dashboard=0
for svc in "${SELECTED_SERVICES[@]}"; do
  if [[ "$svc" == "admin-dashboard" ]]; then
    needs_dashboard=1
    break
  fi
done
if [[ "$needs_dashboard" -eq 1 ]]; then
  echo "==> 预拉取 admin-dashboard 基础镜像..."
  for base in "node:22-bookworm-slim" "gcr.io/distroless/nodejs22-debian12:nonroot"; do
    echo "    pull $base ($PLATFORM) ..."
    if ! docker pull --platform="$PLATFORM" "$base"; then
      echo "警告: 预拉取 $base 失败，build 将继续尝试" >&2
    fi
  done
fi

echo "==> docker compose build ${SERVICE_LIST%/} ..."
DOCKER_BUILDKIT=1 docker compose -f "$COMPOSE_FILE" build "${SELECTED_SERVICES[@]}"

echo "==> 校验镜像架构..."
for img in "${APP_IMAGES[@]}"; do
  if ! docker image inspect "$img" >/dev/null 2>&1; then
    echo "错误: 镜像不存在: $img" >&2
    exit 1
  fi
  arch="$(docker image inspect "$img" --format '{{.Architecture}}')"
  echo "    $img -> $arch"
  if [[ "$arch" != "amd64" ]]; then
    echo "警告: $img 架构为 $arch，预期 amd64（交叉编译可能未生效）" >&2
  fi
done

if [[ "$SAVE_TAR" -eq 0 ]]; then
  echo "==> 跳过 docker save（--no-save）"
  exit 0
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
if [[ ${#SELECTED_SERVICES[@]} -eq ${#ALL_SERVICES[@]} ]]; then
  TAR_BASENAME="company-images-${IMAGE_TAG}-${TIMESTAMP}.tar"
  LATEST_BASENAME="company-images-${IMAGE_TAG}-latest.tar"
else
  SERVICE_SLUG="$(printf '%s-' "${SELECTED_SERVICES[@]}")"
  SERVICE_SLUG="${SERVICE_SLUG%-}"
  TAR_BASENAME="company-images-${SERVICE_SLUG}-${IMAGE_TAG}-${TIMESTAMP}.tar"
  LATEST_BASENAME="company-images-${SERVICE_SLUG}-${IMAGE_TAG}-latest.tar"
fi

TAR_FILE="$OUTPUT_DIR/$TAR_BASENAME"
LATEST_LINK="$OUTPUT_DIR/$LATEST_BASENAME"

echo "==> 导出离线包: $TAR_FILE"
docker save "${APP_IMAGES[@]}" -o "$TAR_FILE"
ln -sfn "$TAR_BASENAME" "$LATEST_LINK"

BYTES="$(wc -c < "$TAR_FILE" | tr -d ' ')"
SIZE_MB=$(( (BYTES + 1024 * 1024 - 1) / 1024 / 1024 ))

cat <<EOF

完成。

离线包:
  $TAR_FILE  (${SIZE_MB} MB)
  $LATEST_LINK -> $TAR_BASENAME

包含镜像:
$(printf '  - %s\n' "${APP_IMAGES[@]}")

阿里云 ECS（示例）:
  scp "$TAR_FILE" user@<ecs-ip>:/opt/company-docker/dist/
  ssh user@<ecs-ip>
  cd /opt/company-docker
  docker load -i dist/$TAR_BASENAME
  docker compose -f docker-compose-amd64.yml up -d

说明:
  - 中间件 postgres / redis / artemis 不在 tar 内，ECS 首次 up 时会从 Hub 拉 amd64 镜像
  - 自研镜像使用 :${IMAGE_TAG} 标签，与本机开发用的 :local 互不干扰
  - 生产密码请修改 .env 中的 POSTGRES_PASSWORD、REDIS_PASSWORD、MQ_PASSWORD 等

EOF
