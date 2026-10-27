FROM tomcat:9.0-jdk17-temurin-noble
RUN groupadd --gid 10001 portfolio && useradd --uid 10001 --gid portfolio --no-create-home portfolio \
    && rm -rf /usr/local/tomcat/webapps/* \
    && chown -R portfolio:portfolio /usr/local/tomcat
COPY --chown=10001:10001 target/portfolio.war /usr/local/tomcat/webapps/portfolio.war
USER 10001:10001
EXPOSE 8080
CMD ["catalina.sh", "run"]
