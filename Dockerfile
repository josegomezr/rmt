# Default ruby in SLES
FROM registry.suse.com/bci/ruby:2.5

# user_id=1000 for simplicity
RUN useradd -r -u 1000 -d /var/lib/rmt -m _rmt
RUN mkdir /srv/www/rmt/ && chown _rmt:root /srv/www/rmt/

RUN zypper --non-interactive install --no-recommends \
        timezone wget gcc-c++ libffi-devel git-core zlib-devel \
        libxml2-devel libxslt-devel cron libmariadb-devel mariadb-client sqlite3-devel \
        vim jq curl bzip2 gzip

RUN update-alternatives --install /usr/bin/ruby ruby /usr/bin/ruby.ruby2.5 0 && \
    update-alternatives --install /usr/bin/bundler bundler /usr/bin/bundler.ruby2.5 0 && \
    update-alternatives --install /usr/bin/bundle bundle /usr/bin/bundle.ruby2.5 0 && \
    update-alternatives --install /usr/bin/gem gem /usr/bin/gem.ruby2.5 0 && \
    update-alternatives --install /usr/bin/irb irb /usr/bin/irb.ruby2.5 0

RUN gem install bundler -v 2.2.34
WORKDIR /srv/www/rmt/
USER _rmt
ENV GEM_HOME "/var/lib/rmt/.bundle"

COPY --chown=_rmt:root Gemfile* /srv/www/rmt/

RUN bundle config build.nokogiri --use-system-libraries && \
    bundle install

COPY --chown=_rmt:root . /srv/www/rmt/

USER root
RUN ln -s /srv/www/rmt/bin/rmt-cli /usr/bin

RUN echo '00000000-0000-4000-0000-000000000000' > /var/lib/rmt/system_uuid

USER _rmt
EXPOSE 4224

CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0", "-p", "4224"]
