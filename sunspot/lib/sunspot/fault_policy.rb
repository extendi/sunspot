# frozen_string_literal: true

require 'logger'

module Sunspot
  #
  # Implement Fault Policy:
  # Takes server using a Round Robin policy from the current live nodes
  #
  module FaultPolicy
    attr_reader :host_index, :current_hostname

    #
    # Get hostname (using RR policy)
    #
    def take_hostname
      # takes all the configured nodes + that one that are derived by solr live config
      selected_hosts = (solr.live_nodes + seed_hosts)
                       .flatten
                       .uniq
                       .reject { |h| faulty?(h) }
                       .sort
      # round robin policy
      # hostname format: <ip | hostname> | <ip | hostname>:<port>
      selected_hosts = seed_hosts if selected_hosts.empty?

      # force host_index to stay in the correct range
      @host_index = @host_index % selected_hosts.size

      @current_hostname = selected_hosts[@host_index]
      current_host = @current_hostname.split(':')
      @host_index = (@host_index + 1) % selected_hosts.size
      if current_host.size == 2
        [current_host.first, current_host.last.to_i]
      else
        current_host + [config.port]
      end
    end

    def seed_hosts
      # uniform seed host
      @seed_hosts ||= config.hostnames.map do |h|
        h = h.split(':')
        if h.size == 2
          "#{h.first}:#{h.last.to_i}"
        else
          "#{h.first}:#{config.port}"
        end
      end
      @seed_hosts
    end

    #
    # Wrap the solr call and retries in case of ConnectionRefused or Http errors
    #
    def with_exception_handling
      retries = 0
      max_retries = @max_retries || 3
      begin
        yield
        # reset counter of faulty_host for the current host
        reset_counter_faulty(@current_hostname)
      rescue RSolr::Error::ConnectionRefused, RSolr::Error::Http => e
        logger.error "Error connecting to Solr #{e.message}"

        # update the map of faulty hosts
        if server_fault_exception?(e)
          update_faulty_host(@current_hostname)
        end

        # clean host in fault state
        clean_faulty_state

        if retries < max_retries
          retries += 1
          sleep_for = 2**retries
          logger.error "Retrying Solr connection in #{sleep_for} seconds... (#{retries} of #{max_retries})"
          sleep(sleep_for)
          retry
        else
          logger.error 'Reached max Solr connection retry count.'
          raise e
        end
      end
    rescue StandardError => e
      logger.error "Exception: #{e.inspect}"
      raise e
    end

    private

      #
      # Return true for the exceptions that indicate that the node is down or not responding.
      #
      # @return [Boolean]
      #
      def server_fault_exception?(e)
        e.is_a?(RSolr::Error::ConnectionRefused) ||
          (e.is_a?(RSolr::Error::Http) && e.response[:status].to_i >= 500)
      end

      #
      # Return true if an host is in fault state.
      # An host is in fault state if and only if:
      # - #number of fault >= 3 TODO ADJUST
      # - time in fault state is 1h
      #
      # @return [Boolean]
      #
      def faulty?(hostname)
        faulty_host_cache_get(hostname).first >= 3
      end

      def reset_counter_faulty(hostname)
        faulty_host_cache_del(hostname)
      end

      def update_faulty_host(hostname)
        cached = faulty_host_cache_set(hostname)
        logger.error "Putting #{hostname} in fault state" if faulty?(hostname)
        cached
      end

      def faulty_host_cache_get(hostname)
        if Sunspot::Admin::Utils.redis_client
          Sunspot::Admin::Utils.redis_client.get(hostname_key(hostname)) || [0, Time.now]
        else
          @faulty_hosts[hostname] || [0, Time.now]
        end
      end

      def faulty_host_cache_set(hostname, expires_in: 1.hour.to_i)
        if Sunspot::Admin::Utils.redis_client
          status = faulty_host_cache_get(hostname)
          status[0] += 1
          status[1] = Time.now
          Sunspot::Admin::Utils.redis_client.set(hostname_key(hostname), status, expires_in: expires_in)
          status
        else
          @faulty_hosts ||= {}
          @faulty_hosts[hostname] ||= [0, Time.now]
          @faulty_hosts[hostname][0] += 1
          @faulty_hosts[hostname][1] = Time.now
          @faulty_hosts[hostname]
        end
      end

      def faulty_host_cache_del(hostname)
        if Sunspot::Admin::Utils.redis_client
          Sunspot::Admin::Utils.redis_client.del(hostname_key(hostname))
        else
          @faulty_hosts.delete(hostname)
        end
      end

      #
      # Remove the host from @faulty_host cache that are too old.
      # Does not do anything if Rails.cache is used
      #
      def clean_faulty_state
        unless Sunspot::Admin::Utils.redis_client
          @faulty_hosts.select! do |_k, v|
            (Time.now - v[1]).to_i < 3600
          end
        end
      end

      def hostname_key(hostname)
        "#{Digest::MD5.hexdigest(hostname)[0..9]}_CACHE_FAULTY_NODES"
      end

      def logger
        @logger ||= ::Rails.logger if defined?(::Rails)
        @logger ||= Logger.new(STDOUT)
      end
  end
end
