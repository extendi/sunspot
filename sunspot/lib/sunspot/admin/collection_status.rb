require_relative 'utils'

module Sunspot
  module Admin
    #
    # Collections Maintenance
    #
    module Collection
      #
      # Retrieve stats for all collections
      #
      # @param [Symbol] :as <:json, :table>
      #
      # Example: retrieve_stats(as: :table)
      #
      def retrieve_stats(as: :json)
        stats = retrieve_stats_as_json
        case as
        when :json
          stats
        when :table
          s_stats = stats.sort do |a, b|
            b[:deleted_perc] <=> a[:deleted_perc]
          end

          table = Terminal::Table.new(
            headings: ['Collection', 'Has deletions', '# Docs', '# Max Docs', '# Deleted'],
            rows: s_stats.map do |row|
              [
                row[:collection_name],
                row[:has_deletions],
                row[:num_docs],
                row[:max_docs],
                format('%d (%.2f%%)', row[:deleted_docs], row[:deleted_perc])
              ]
            end
          )
          puts table
        end
      end

      #
      # Optimize a single collection given the collection name
      #
      # @param [String] collection_name: the name of the collection
      #
      # @return [RSolrResponse]
      #
      def optimize_collection(collection_name:)
        uri = connection.uri
        c = RSolr.connect(url: "http://#{uri.host}:#{uri.port}/solr/#{collection_name}")
        begin
          response = c.get 'update', params: {
            _: (Time.now.to_f * 1000).to_i,
            commit: true,
            optimize: true
          }

          # destroy cache for that collection
          Utils.remove_key_from_cache(
            calc_key_collection_stats(collection_name)
          )
          response
        rescue RSolr::Error::Http => _e
          nil
        end
      end

      #
      # Optimize all collections using a threshold of deleted docs
      #
      # @param [Number] deleted_threshold: call optimize_collection if the deleted_docs fragmentation is above the threshold
      # @param [Bool] reload: if true reload the collection after optimization
      #
      def optimize_collections(deleted_threshold: 10, reload: false)
        retrieve_stats_as_json
          .select { |e| e[:deleted_perc] > deleted_threshold }
          .each do |e|
            c = e[:collection_name]
            puts "Optimizing #{c}"
            optimize_collection(collection_name: c)
            reload_collection(collection_name: c, refresh_list: false) if reload
          end
      end

      #
      # Retrieve stats for the given collection
      #
      # @param [String] collection_name: is the collection name
      #
      # @return [Hash] stats info
      #
      def retrieve_stats_for(collection_name:)
        Utils.with_cache(force: false, key: calc_key_collection_stats(collection_name), default: {}, expires_in: 300) do
          uri = connection.uri
          c = RSolr.connect(url: "http://#{uri.host}:#{uri.port}/solr/#{collection_name}")
          begin
            response = c.get 'admin/luke', params: {
              _: (Time.now.to_f * 1000).to_i,
              numTerms: 0,
              show: 'index'
            }

            response = response['index']
            del_perc =
              response['numDocs'].to_i > 0 ? (100 * response['deletedDocs'].to_f / response['numDocs'].to_f) : 0

            {
              has_deletions: response['hasDeletions'],
              max_docs: response['maxDoc'].to_i,
              num_docs: response['numDocs'].to_i,
              deleted_docs: response['deletedDocs'].to_i,
              deleted_perc: del_perc
            }
          rescue RSolr::Error::Http => _e
            nil
          end
        end
      end

      ################################ PRIVATE ###################################

      private

      def retrieve_stats_as_json
        collections(force: true)
          .map do |c|
            retrieve_stats_for(collection_name: c).merge(collection_name: c)
          end
          .compact
      end

      def calc_key_collection_stats(collection_name)
        "CACHE_SOLR_COLLECTION_STATS_#{collection_name}"
      end
    end
  end
end
