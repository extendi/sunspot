module Sunspot
  module Admin
    class Utils
      # Helper function for solr caching
      def self.with_cache(force: false, key:, retries: 0, max_retries: 3, default: nil, expires_in:)
        return default if retries >= max_retries

        r =
          if defined?(::Rails.cache)
            ::Rails.cache.fetch(key, expires_in: expires_in, force: force) { yield }
          else
            yield
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

      def self.solr_request(connection, action, extra_params: {})
        connection.get(
          :collections,
          params: { action: action, wt: 'json' }.merge(extra_params)
        )
      end

      def self.remove_key_from_cache(key)
        ::Rails.cache.delete(key) if defined?(::Rails.cache)
      end
    end
  end
end
