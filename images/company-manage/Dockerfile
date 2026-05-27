# syntax=docker/dockerfile:1
# 构建上下文：company-parent 根目录
FROM maven:3.9-eclipse-temurin-21-alpine AS build
WORKDIR /build

COPY company-manage/pom.xml ./pom.xml
COPY company-manage/src ./src

RUN mvn -DskipTests package -q

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

RUN addgroup -S app && adduser -S app -G app
COPY --from=build /build/target/company-manage-1.0.0.jar /app/app.jar
USER app
EXPOSE 8088

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
