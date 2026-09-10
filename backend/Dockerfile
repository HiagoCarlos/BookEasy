# ---------- Etapa 1: build ----------
FROM maven:3.9-eclipse-temurin-25 AS build
WORKDIR /app

# Copia só o pom primeiro pra aproveitar cache de dependências
COPY pom.xml .
RUN mvn dependency:go-offline -B

COPY src ./src
RUN mvn clean package -DskipTests -B

# ---------- Etapa 2: runtime ----------
FROM eclipse-temurin:25-jre-noble
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]