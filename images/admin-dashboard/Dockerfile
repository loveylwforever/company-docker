# syntax=docker/dockerfile:1
# 构建上下文：company-parent 根目录（见 docker-compose.yml build.context）
# 运行镜像仅含 Nitro .output，无需 node_modules（已移除 xlsx 等运行时外部依赖）
FROM node:22-alpine AS build
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@11.2.2 --activate

COPY company-admin-dashboard/package.json \
  company-admin-dashboard/pnpm-lock.yaml \
  company-admin-dashboard/pnpm-workspace.yaml \
  ./
# pnpm 11：workspace 中 allowBuilds 默认禁用部分包脚本，容器内需显式放行
RUN pnpm install --frozen-lockfile --config.dangerouslyAllowAllBuilds=true

COPY company-admin-dashboard/ .

ARG NODE_HEAP_MB=2048
ENV NODE_ENV=production
ENV NODE_OPTIONS=--max-old-space-size=${NODE_HEAP_MB}
RUN pnpm run build

FROM node:22-alpine AS runtime
WORKDIR /app
RUN apk add --no-cache wget

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=3000
ENV NITRO_PORT=3000

COPY --from=build /app/.output ./.output

EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=5s --retries=8 --start-period=30s \
  CMD wget -qO- http://127.0.0.1:3000/ >/dev/null 2>&1 || exit 1

CMD ["node", ".output/server/index.mjs"]
