FROM ruby:3.4.8-slim AS build
WORKDIR /rails
RUN apt-get update -qq && apt-get install --no-install-recommends -y build-essential libyaml-dev libsqlite3-dev pkg-config && rm -rf /var/lib/apt/lists/*
ENV RAILS_ENV=production BUNDLE_DEPLOYMENT=1 BUNDLE_PATH=/usr/local/bundle BUNDLE_WITHOUT=development:test
COPY Gemfile Gemfile.lock ./
RUN bundle install
COPY . .
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile

FROM ruby:3.4.8-slim
WORKDIR /rails
RUN apt-get update -qq && apt-get install --no-install-recommends -y libyaml-0-2 libsqlite3-0 && rm -rf /var/lib/apt/lists/* && groupadd --gid 1000 rails && useradd --uid 1000 --gid 1000 --create-home rails
ENV RAILS_ENV=production BUNDLE_DEPLOYMENT=1 BUNDLE_PATH=/usr/local/bundle BUNDLE_WITHOUT=development:test DATABASE_PATH=/rails/storage/production.sqlite3
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build --chown=rails:rails /rails /rails
USER rails
EXPOSE 3000
CMD ["bin/rails", "server", "-b", "0.0.0.0"]
