# frozen_string_literal: true

module Sunspot
  module Admin
    class Utils

      class << self

        # Helper function for solr caching
        def with_cache(force: false, key:, retries: 0, max_retries: 3, default: nil, expires_in:)
          return default if retries >= max_retries

          r =
            if force
              yield
            elsif redis_client
              cached = redis_client.get(key)
              if cached.nil?
                cached = yield
                redis_client.set(key, cached, expires_in: expires_in)
              end
              cached
            else
              @cached ||= {}
              time = Time.now
              if !@cached[key].present? || (time - (@cached[:time] || time)) > expires_in
                @cached[key] = yield
                @cached[:time] = time
              end
              @cached[key]
            end

          if r.nil?
            with_cache(
              force: true,
              key: key,
              retries: retries + 1,
              max_retries: max_retries,
              default: default,
              expires_in: expires_in
            ) { yield }
          else
            r
          end
        end

        def solr_request(connection, action, extra_params: {})
          connection.get(
            :collections,
            params: { action: action, wt: 'json' }.merge(extra_params)
          )
        end

        def cache_del(key)
          if redis_client
            redis_client.del(key)
          else
            @cached[key] = nil
          end
        end

        REDIS_CLUSTER_STATUS_DB = 5

        def redis_client
          if defined?(::Rails.cache) && ::Rails.cache.respond_to?(:redis_options)
            opts = ::Rails.cache.redis_options.merge({
              db: REDIS_CLUSTER_STATUS_DB,
              compress: true
            })
            @@redis_client ||= Redis::Store.new(opts)
          else
            nil
          end
        end

      end
    end
  end
end
