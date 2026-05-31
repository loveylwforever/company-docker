# syntax=docker/dockerfile:1
# 构建上下文：company-parent 根目录（见 docker-compose.yml build.context）
FROM maven:3.9-eclipse-temurin-21-alpine AS build
WORKDIR /build

COPY pom.xml .
COPY company-base/pom.xml company-base/pom.xml
COPY company-mq/pom.xml company-mq/pom.xml
COPY company-auth/pom.xml company-auth/pom.xml
COPY company-auth-channel/pom.xml company-auth-channel/pom.xml
COPY company-manage/pom.xml company-manage/pom.xml

COPY company-base/src company-base/src
COPY company-manage/src company-manage/src

RUN mvn -pl company-manage -am -DskipTests package -q

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

RUN addgroup -S app && adduser -S app -G app
COPY --from=build /build/company-manage/target/company-manage-1.0.0-exec.jar /app/app.jar
USER app
EXPOSE 8088

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
