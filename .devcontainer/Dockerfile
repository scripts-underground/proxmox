FROM mcr.microsoft.com/devcontainers/ruby:3.3-bookworm

RUN apt-get update && apt-get install -y tini shellcheck shfmt python3-pip && \
    gem install bundler webrick && \
    bundle config set path.system true && \
    pip3 install pre-commit --break-system-packages

# Install Go for AST tool
RUN curl -fsSL https://go.dev/dl/go1.24.0.linux-amd64.tar.gz -o /tmp/go.tar.gz && \
    rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm /tmp/go.tar.gz && \
    ln -sf /usr/local/go/bin/go /usr/local/bin/go

RUN cat > /tmp/Gemfile << 'GEMFILE'
source "https://rubygems.org"
gem "jekyll", "~> 4.4"
gem "jekyll-github-metadata"
gem "jekyll-seo-tag"
gem "jekyll-feed"
gem "webrick"
gem "nokogiri"
GEMFILE

RUN cd /tmp && bundle install

WORKDIR /workspaces/scripts-underground-proxmox
ENV BUNDLE_GEMFILE=/tmp/Gemfile

RUN mv /bin/sh /bin/sh.real && \
    cat > /bin/sh << 'WRAPPER' && \
    chmod +x /bin/sh
#!/bin/sh.real
if [ -f /workspaces/scripts-underground-proxmox/_config.yml ]; then
  curl -sf http://localhost:4000 > /dev/null 2>&1 || {
    tini -s -- jekyll serve \
      --config /workspaces/scripts-underground-proxmox/_config.yml,/workspaces/scripts-underground-proxmox/_config.dev.yml \
      --host 0.0.0.0 \
      --livereload \
      > /tmp/jekyll.log 2>&1 &
    TINI_PID=$!
  }
fi

trap 'kill $TINI_PID 2>/dev/null; exit 0' TERM
exec /bin/sh.real "$@"
WRAPPER

ENTRYPOINT ["/bin/sh"]
CMD ["-c", "exec sleep infinity"]
