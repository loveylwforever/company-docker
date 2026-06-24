# syntax=docker/dockerfile:1
# 构建上下文：company-parent 根目录（见 docker-compose.yml build.context）
# 运行镜像仅含 Nitro .output（distroless）；构建阶段用 bookworm-slim（与 distroless debian 同系，不用 alpine）
FROM node:22-bookworm-slim AS build
WORKDIR /app
RUN corepack enable && corepack prepare pnpm@11.2.2 --activate

COPY company-admin-dashboard/package.json \
  company-admin-dashboard/pnpm-lock.yaml \
  company-admin-dashboard/pnpm-workspace.yaml \
  ./
# pnpm 11：workspace 中 allowBuilds 默认禁用部分包脚本，容器内需显式放行
RUN pnpm install --frozen-lockfile --config.dangerouslyAllowAllBuilds=true

COPY company-admin-dashboard/ .

# 字体文件须全局可读，避免 Nitro 以 node 用户运行时 403（历史上 DingTalk ttf 曾为 600）
RUN chmod -R a+rX app/assets/fonts 2>/dev/null || true

ARG NODE_HEAP_MB=2048
ENV NODE_ENV=production
ENV NODE_OPTIONS=--max-old-space-size=${NODE_HEAP_MB}
RUN pnpm run build

# 运行层：distroless 仅含 Node 运行时 + .output，无 shell/apk，攻击面更小
FROM gcr.io/distroless/nodejs22-debian12:nonroot
WORKDIR /app

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=3000
ENV NITRO_PORT=3000

COPY --from=build --chown=nonroot:nonroot /app/.output ./.output
COPY --chown=nonroot:nonroot company-docker/images/admin-dashboard/healthcheck.mjs ./healthcheck.mjs

EXPOSE 3000

# distroless 无 wget；ENTRYPOINT 已是 node，HEALTHCHECK 须写全路径（见镜像内 /nodejs/bin/node）
HEALTHCHECK --interval=15s --timeout=5s --retries=8 --start-period=30s \
  CMD ["/nodejs/bin/node", "/app/healthcheck.mjs"]

CMD ["/app/.output/server/index.mjs"]
