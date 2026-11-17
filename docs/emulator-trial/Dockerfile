# Image used by the trial in docs/emulator-trial.md. AWS publishes no prebuilt image; this is the
# Dockerfile from its user guide ("Getting started with Docker") with one change: the package is copied
# from a local file whose GPG signature was checked first, instead of being fetched by ADD from the URL.
#
# Build from the folder that holds the package:
#   docker build -t aws-emulator-trial -f <repo>/docs/emulator-trial/Dockerfile .
# On an x86-64 machine add: --build-arg PACKAGE=aws-emulator-x86_64.rpm
FROM public.ecr.aws/amazonlinux/amazonlinux:2023-minimal
ARG PACKAGE=aws-emulator-aarch64.rpm
COPY ${PACKAGE} /tmp/aws-emulator.rpm
RUN rpm -i /tmp/aws-emulator.rpm && rm /tmp/aws-emulator.rpm \
    && mkdir -p /home/emulator && chown 1000 /home/emulator
USER 1000
ENV HOME=/home/emulator
EXPOSE 9297
ENTRYPOINT ["aws-emulator", "-b", "0.0.0.0"]
