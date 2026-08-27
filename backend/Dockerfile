# Backend image. Two stages so the runtime carries a JRE and one jar rather than
# Maven, a JDK and a ~500MB dependency cache.
#
# The dependency layer is resolved before the sources are copied, so editing Java
# does not re-download the world on every build -- which matters when the build
# runs on the same small box that serves the game.

FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /build

# Resolve dependencies against the POM alone; this layer is cached until the POM
# changes.
COPY pom.xml .
RUN mvn -B -ntp dependency:go-offline

COPY src ./src
# Tests need a live Postgres and an HTTP port, which a build container has
# neither of. They run in CI and on the developer's machine, not here.
RUN mvn -B -ntp -DskipTests package \
    && cp target/*.jar /build/app.jar

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

# Runs unprivileged: the process needs nothing but its own jar and a socket.
RUN addgroup -S jeopard && adduser -S -G jeopard jeopard
COPY --from=build /build/app.jar app.jar
USER jeopard

EXPOSE 8080

# MaxRAMPercentage rather than a fixed -Xmx: the JVM then adapts to whatever the
# container is given instead of being tuned for one box.
ENV JAVA_OPTS="-XX:MaxRAMPercentage=70 -XX:+UseSerialGC"

# The seeder inserts 2,760 clues on a first start, so the health check has to
# tolerate a slow first boot -- hence start-period rather than a long interval.
HEALTHCHECK --interval=15s --timeout=4s --start-period=90s --retries=4 \
    CMD wget -q -O- http://127.0.0.1:8080/actuator/health | grep -q '"status":"UP"'

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar app.jar"]
