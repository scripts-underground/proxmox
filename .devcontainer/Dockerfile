FROM mcr.microsoft.com/devcontainers/ruby:3.3-bookworm

RUN apt-get update && apt-get install -y tini shellcheck shfmt python3-pip && \
    gem install bundler webrick && \
    bundle config set path.system true && \
    pip3 install pre-commit --break-system-packages

# Install Go for AST tool
RUN curl -fsSL https://go.dev/dl/go1.25.0.linux-amd64.tar.gz -o /tmp/go.tar.gz && \
    rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm /tmp/go.tar.gz && \
    ln -sf /usr/local/go/bin/go /usr/local/bin/go

COPY Gemfile /tmp/Gemfile

RUN cd /tmp && bundle install

WORKDIR /workspaces/scripts-underground-proxmox
ENV BUNDLE_GEMFILE=/tmp/Gemfile

RUN mv /bin/sh /bin/sh.real
COPY sh-wrapper /bin/sh
RUN chmod +x /bin/sh

ENTRYPOINT ["/bin/sh"]
CMD ["-c", "exec sleep infinity"]
