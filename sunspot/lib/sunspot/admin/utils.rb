# frozen_string_literal: true

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
            @cached ||= {}
            if force
              yield
            else
              time = Time.now
              if !@cached[key].present? || (time - (@cached[:time] || time)) > expires_in
                @cached[key] = yield
                @cached[:time] = time
              end
              @cached[key]
            end
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
        if defined?(::Rails.cache)
          ::Rails.cache.delete(key)
        else
          @cached[key] = nil
        end
      end
    end
  end
end
