module Sunspot
  # The Sunspot::Configuration module provides a factory method for Sunspot
  # configuration objects. Available properties are:
  #
  # Sunspot.config.solr.url::
  #   The URL at which to connect to Solr
  #   (default: 'http://localhost:8983/solr')
  # Sunspot.config.pagination.default_per_page::
  #   Solr always paginates its results. This sets Sunspot's default result
  #   count per page if it is not explicitly specified in the query.
  # Sunspot.config.indexing.default_batch_size::
  #   This sets the batch size for indexing, default is 50
  #
  module Configuration
    class <<self
      # Factory method to build configuration instances.
      #
      # ==== Returns
      #
      # LightConfig::Configuration:: new configuration instance with defaults
      #
      def build #:nodoc:
        conf = LightConfig.build do
          solr do
            url 'http://127.0.0.1:8983/solr/default'
            hostnames ['127.0.0.1']
            port 8983
            read_timeout nil
            open_timeout nil
            proxy nil
            update_format :xml
          end
          master_solr do
            url nil
          end
          pagination do
            default_per_page 30
          end
          indexing do
            default_batch_size 50
          end
          proxy nil
          collection do
            base_name 'base'
            num_shards 1
            replication_factor 1
            max_shards_per_node 2
            config_name 'default'
          end
        end

        # helper
        class <<conf
          def hostname
            return solr.hostnames[0] unless solr.hostnames.empty?

            'locahost'
          end

          def hostnames
            hosts = solr.hostnames
            if hosts.is_a?(Array)
              hosts
            else
              hosts.split(',')
            end
          end

          def port
            solr.port
          end

          def read_timeout
            solr.read_timeout
          end

          def open_timeout
            solr.open_timeout
          end

          def collection_param(id)
            begin
              collection.send(id.to_sym)
            rescue
              nil
            end
          end
        end

        class <<conf.collection
          def [](id)
            begin
              self.send(id.to_sym)
            rescue
              nil
            end
          end
        end

        conf
      end

      # Location for the default solr configuration files,
      # required for bootstrapping a new solr installation
      #
      # ==== Returns
      #
      # String:: Directory with default solr config files
      #
      def solr_default_configuration_location
        File.join(File.dirname(__FILE__), '../../solr/solr/conf')
      end
    end
  end
end
