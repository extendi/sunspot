#!/bin/sh

set +e

solr_responding() {
  curl -o /dev/null "http://localhost:$SOLR_PORT/solr/default/admin/ping" > /dev/null 2>&1
}

# if [ !solr_responding ]; then
#     exit 1
# fi

case $GEM in
  "sunspot")
    cd sunspot
    bundle install --quiet --path vendor/bundle

    # Invoke the sunspot specs
    bundle exec appraisal install && bundle exec appraisal rake spec
    rv=$?

    exit $rv
    ;;

  "sunspot_rails")
    cd sunspot
    bundle install --quiet --path vendor/bundle

    cd ../sunspot_rails
    bundle install --quiet --path vendor/bundle
    bundle exec appraisal install && bundle exec appraisal rspec
    rv=$?

    exit $rv
    ;;
  *)
esac
