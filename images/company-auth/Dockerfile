# syntax=docker/dockerfile:1
# 构建上下文：company-parent 根目录（见 docker-compose.yml build.context）
FROM maven:3.9-eclipse-temurin-21-alpine AS build
WORKDIR /build

COPY pom.xml .
COPY company-base/pom.xml company-base/pom.xml
COPY company-mq/pom.xml company-mq/pom.xml
COPY company-auth/pom.xml company-auth/pom.xml
COPY company-auth-channel/pom.xml company-auth-channel/pom.xml

COPY company-base/src company-base/src
COPY company-mq/src company-mq/src
COPY company-auth/src company-auth/src

RUN mvn -pl company-auth -am -DskipTests package -q

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

RUN addgroup -S app && adduser -S app -G app \
  && mkdir -p /var/lib/company-auth/fail-insert-trans-info /var/log/auth/history \
  && chown -R app:app /var/lib/company-auth /var/log/auth

COPY --from=build /build/company-auth/target/company-auth-1.0.0-exec.jar /app/app.jar

USER app
EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
