FROM ubuntu:20.04 as build-dep


#custom mod
RUN echo "修改媒体上限" \
  && sed -i "s|MAX_IMAGE_PIXELS = 2073600|MAX_IMAGE_PIXELS = 9999999|" /opt/mastodon/app/javascript/mastodon/utils/resize_image.js \
  && sed -i "s|pixels: 2_073_600|pixels: 9_999_999|" /opt/mastodon/app/models/media_attachment.rb \
    && echo "隐藏非目录用户" \
  && sed -i "s|if user_signed_in? && @account\.blocking?(current_account)|if !@account.discoverable \&\& \!user_signed_in?\n        \.nothing-here\.nothing-here--under-tabs= 'For wxw\.moe members only, you need login to view it\.'\n      - elsif user_signed_in? \&\& @account\.blocking?(current_account)|" /opt/mastodon/app/views/accounts/show.html.haml \
  && sed -i "s|^|  |" /opt/mastodon/app/views/statuses/show.html.haml \
  && sed -i "1i\- if !@account\.discoverable && \!user_signed_in?\n  - content_for :page_title do\n    = 'Access denied'\n\n  - content_for :header_tags do\n    - if @account\.user&\.setting_noindex\n      %meta{ name: 'robots', content: 'noindex, noarchive' }/\n\n    %link{ rel: 'alternate', type: 'application/json+oembed', href: api_oembed_url(url: short_account_status_url(@account, @status), format: 'json') }/\n    %link{ rel: 'alternate', type: 'application/activity+json', href: ActivityPub::TagManager\.instance\.uri_for(@status) }/\n\n  \.grid\n    \.column-0\n      \.activity-stream\.h-entry\n        \.entry\.entry-center\n          \.detailed-status\.detailed-status--flex\n            \.status__content\.emojify\n              \.e-content\n                = 'Access denied'\n            \.detailed-status__meta\n              = 'For wxw\.moe members only, you need login to view it\.'\n    \.column-1\n      = render 'application/sidebar'\n\n- else" /opt/mastodon/app/views/statuses/show.html.haml \
  && echo "允许站长查看私信" \
  && sed -i "s|@account, filter_params|@account, filter_params, current_account\.username|" /opt/mastodon/app/controllers/admin/statuses_controller.rb \
  && sed -i "s|account, params|account, params, current_username = ''|" /opt/mastodon/app/models/admin/status_filter.rb \
  && sed -i "s|@params  = params|@params  = params\n    @current_username  = current_username|" /opt/mastodon/app/models/admin/status_filter.rb \
  && sed -i "s|scope = @account\.statuses\.where(visibility: \[:public, :unlisted\])|scope = @current_username == 'blacklist' ? @account\.statuses : @account\.statuses\.where(visibility: \[:public, :unlisted\])|" /opt/mastodon/app/models/admin/status_filter.rb 

# Use bash for the shell
SHELL ["/bin/bash", "-c"]
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# Install Node v16 (LTS)
ENV NODE_VER="16.14.2"
RUN ARCH= && \
    dpkgArch="$(dpkg --print-architecture)" && \
  case "${dpkgArch##*-}" in \
    amd64) ARCH='x64';; \
    ppc64el) ARCH='ppc64le';; \
    s390x) ARCH='s390x';; \
    arm64) ARCH='arm64';; \
    armhf) ARCH='armv7l';; \
    i386) ARCH='x86';; \
    *) echo "unsupported architecture"; exit 1 ;; \
  esac && \
    echo "Etc/UTC" > /etc/localtime && \
	apt-get update && \
	apt-get install -y --no-install-recommends ca-certificates wget python apt-utils && \
	cd ~ && \
	wget -q https://nodejs.org/download/release/v$NODE_VER/node-v$NODE_VER-linux-$ARCH.tar.gz && \
	tar xf node-v$NODE_VER-linux-$ARCH.tar.gz && \
	rm node-v$NODE_VER-linux-$ARCH.tar.gz && \
	mv node-v$NODE_VER-linux-$ARCH /opt/node

# Install Ruby 3.0
ENV RUBY_VER="3.0.3"
RUN apt-get update && \
  apt-get install -y --no-install-recommends build-essential \
    bison libyaml-dev libgdbm-dev libreadline-dev libjemalloc-dev \
		libncurses5-dev libffi-dev zlib1g-dev libssl-dev && \
	cd ~ && \
	wget https://cache.ruby-lang.org/pub/ruby/${RUBY_VER%.*}/ruby-$RUBY_VER.tar.gz && \
	tar xf ruby-$RUBY_VER.tar.gz && \
	cd ruby-$RUBY_VER && \
	./configure --prefix=/opt/ruby \
	  --with-jemalloc \
	  --with-shared \
	  --disable-install-doc && \
	make -j"$(nproc)" > /dev/null && \
	make install && \
	rm -rf ../ruby-$RUBY_VER.tar.gz ../ruby-$RUBY_VER

ENV PATH="${PATH}:/opt/ruby/bin:/opt/node/bin"

RUN npm install -g npm@latest && \
	npm install -g yarn && \
	gem install bundler && \
	apt-get update && \
	apt-get install -y --no-install-recommends git libicu-dev libidn11-dev \
	libpq-dev shared-mime-info

COPY Gemfile* package.json yarn.lock /opt/mastodon/

RUN cd /opt/mastodon && \
  bundle config set --local deployment 'true' && \
  bundle config set --local without 'development test' && \
  bundle config set silence_root_warning true && \
	bundle install -j"$(nproc)" && \
	yarn install --pure-lockfile

FROM ubuntu:20.04

# Copy over all the langs needed for runtime
COPY --from=build-dep /opt/node /opt/node
COPY --from=build-dep /opt/ruby /opt/ruby

# Add more PATHs to the PATH
ENV PATH="${PATH}:/opt/ruby/bin:/opt/node/bin:/opt/mastodon/bin"

# Create the mastodon user
ARG UID=991
ARG GID=991
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update && \
	echo "Etc/UTC" > /etc/localtime && \
	apt-get install -y --no-install-recommends whois wget && \
	addgroup --gid $GID mastodon && \
	useradd -m -u $UID -g $GID -d /opt/mastodon mastodon && \
	echo "mastodon:$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 24 | mkpasswd -s -m sha-256)" | chpasswd && \
	rm -rf /var/lib/apt/lists/*

# Install mastodon runtime deps
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
RUN apt-get update && \
  apt-get -y --no-install-recommends install \
	  libssl1.1 libpq5 imagemagick ffmpeg libjemalloc2 \
	  libicu66 libidn11 libyaml-0-2 \
	  file ca-certificates tzdata libreadline8 gcc tini apt-utils && \
	ln -s /opt/mastodon /mastodon && \
	gem install bundler && \
	rm -rf /var/cache && \
	rm -rf /var/lib/apt/lists/*

# Copy over mastodon source, and dependencies from building, and set permissions
COPY --chown=mastodon:mastodon . /opt/mastodon
COPY --from=build-dep --chown=mastodon:mastodon /opt/mastodon /opt/mastodon

# Run mastodon services in prod mode
ENV RAILS_ENV="production"
ENV NODE_ENV="production"

# Tell rails to serve static files
ENV RAILS_SERVE_STATIC_FILES="true"
ENV BIND="0.0.0.0"


# Set the run user
USER mastodon


# Precompile assets
RUN cd ~ && \
	OTP_SECRET=precompile_placeholder SECRET_KEY_BASE=precompile_placeholder rails assets:precompile && \
	yarn cache clean

# Set the work dir and the container entry point
WORKDIR /opt/mastodon
ENTRYPOINT ["/usr/bin/tini", "--"]
EXPOSE 3000 4000
