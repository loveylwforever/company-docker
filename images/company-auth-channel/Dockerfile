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
    mvn -pl company-auth-channel -am dependency:go-offline -DskipTests -B

COPY company-base/src company-base/src
COPY company-mq/src company-mq/src
COPY company-auth/src company-auth/src
COPY company-auth-channel/src company-auth-channel/src

RUN --mount=type=cache,target=/root/.m2/repository \
    mvn -pl company-auth-channel -am -DskipTests package -B -q

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

RUN addgroup -S app && adduser -S app -G app \
  && mkdir -p /data/plugins /var/log/auth-channel/history \
  && chown -R app:app /data/plugins /var/log/auth-channel

COPY --from=build /build/company-auth-channel/target/company-auth-channel-1.0.0-exec.jar /app/app.jar

USER app
EXPOSE 8090

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
