# syntax=docker/dockerfile:1
# 构建上下文：company-parent 根目录（见 docker-compose.yml build.context）
FROM maven:3.9-eclipse-temurin-21-alpine AS build
WORKDIR /build

COPY company-docker/maven/settings.xml /root/.m2/settings.xml

COPY pom.xml .
COPY company-base/pom.xml company-base/pom.xml
COPY company-mq/pom.xml company-mq/pom.xml
COPY company-auth/pom.xml company-auth/pom.xml
COPY company-auth-channel/pom.xml company-auth-channel/pom.xml
COPY company-manage/pom.xml company-manage/pom.xml

RUN --mount=type=cache,target=/root/.m2/repository \
    mvn -pl company-manage -am dependency:go-offline -DskipTests -B

COPY company-base/src company-base/src
COPY company-manage/src company-manage/src

RUN --mount=type=cache,target=/root/.m2/repository \
    mvn -pl company-manage -am -DskipTests package -B -q

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

RUN apk add --no-cache wget \
  && addgroup -S app && adduser -S app -G app \
  && mkdir -p /var/log/company-manage/history \
  && chown -R app:app /var/log/company-manage

COPY --from=build /build/company-manage/target/company-manage-1.0.0-exec.jar /app/app.jar
USER app
EXPOSE 8088

HEALTHCHECK --interval=15s --timeout=5s --retries=5 --start-period=90s \
  CMD wget -qO- http://127.0.0.1:8088/tools/ping >/dev/null 2>&1 || exit 1

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
