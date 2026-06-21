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
    mvn -pl company-auth -am dependency:go-offline -DskipTests -B

COPY company-base/src company-base/src
COPY company-mq/src company-mq/src
COPY company-auth/src company-auth/src

RUN --mount=type=cache,target=/root/.m2/repository \
    mvn -pl company-auth -am -DskipTests package -B -q

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

# channel-plugin generate.sh requires bash, zip, and file(1)
RUN apk add --no-cache bash zip file \
  && addgroup -S app && adduser -S app -G app \
  && mkdir -p /var/lib/company-auth/fail-insert-trans-info /var/log/company-auth/history \
  && chown -R app:app /var/lib/company-auth /var/log/company-auth

COPY --from=build /build/company-auth/target/company-auth-1.0.0-exec.jar /app/app.jar

USER app
EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
