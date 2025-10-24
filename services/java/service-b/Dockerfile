FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn clean package -DskipTests

FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

# Download OpenTelemetry Java Agent
ADD https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.0.0/opentelemetry-javaagent.jar /app/opentelemetry-javaagent.jar

# Copy the application JAR
COPY --from=build /app/target/*.jar app.jar

# Expose application and metrics ports
EXPOSE 8080 9464

# Default OpenTelemetry configuration
ENV OTEL_SERVICE_NAME=service-b \
    OTEL_TRACES_EXPORTER=otlp \
    OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://otel-collector.monitoring.svc.cluster.local:4317 \
    OTEL_EXPORTER_OTLP_TRACES_PROTOCOL=grpc \
    OTEL_EXPORTER_OTLP_TRACES_INSECURE=true \
    OTEL_METRICS_EXPORTER=prometheus \
    OTEL_EXPORTER_PROMETHEUS_HOST=0.0.0.0 \
    OTEL_EXPORTER_PROMETHEUS_PORT=9464 \
    OTEL_LOGS_EXPORTER=none

# Run the application with OTEL agent
ENTRYPOINT ["java", "-javaagent:/app/opentelemetry-javaagent.jar", "-jar", "app.jar"]
