# syntax=docker/dockerfile:1
# 构建上下文：company-parent 根目录
FROM maven:3.9-eclipse-temurin-21-alpine AS build
WORKDIR /build

COPY pom.xml .
COPY company-base/pom.xml company-base/pom.xml
COPY company-base/src company-base/src
COPY company-manage/pom.xml company-manage/pom.xml
COPY company-manage/src company-manage/src

RUN mvn -f pom.xml install -N -DskipTests -q \
  && mvn -f company-base/pom.xml install -DskipTests -q \
  && mvn -f company-manage/pom.xml package -DskipTests -q

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

RUN addgroup -S app && adduser -S app -G app
COPY --from=build /build/company-manage/target/company-manage-1.0.0.jar /app/app.jar
USER app
EXPOSE 8088

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
