# frozen_string_literal: true

require 'logger'
require 'terminal-table'
require 'json'

module Sunspot
  class AdminSession < Session
    #
    # AdminSession connect direclty to the admin Solr endpoint
    # to handle admin stuff like collections listing, creation, etc...
    #

    CREATE_COLLECTION_MAP = {
      async: 'async',
      auto_add_replicas: 'autoAddReplicas',
      config_name: 'collection.configName',
      max_shards_per_node: 'maxShardsPerNode',
      create_node_set: 'createNodeSet',
      create_node_set_shuffle: 'createNodeSet.shuffle',
      num_shards: 'numShards',
      property_name: 'property.name',
      replication_factor: 'replicationFactor',
      router_field: 'router.field',
      router_name: 'router.name',
      rule: 'rule',
      shards: 'shards',
      snitch: 'snitch'
    }.freeze
    
    attr_accessor :replicas_not_active

    def initialize(config:, refresh_every: 600)
      @initialized_at = Time.now
      @refresh_every = refresh_every
      @config = config
      @replicas_not_active = []
    end

    #
    # Return the appropriate admin session
    def session
      c = Sunspot::Configuration.build
      host_port = @config.hostnames[rand(@config.hostnames.size)].split(':')
      host_port = [host_port.first, host_port.last.to_i] if host_port.size == 2
      host_port = [host_port.first, @config.port] if host_port.size == 1

      c.solr.url = URI::HTTP.build(
        host: host_port.first,
        port: host_port.last,
        path: '/solr/admin'
      ).to_s
      c.solr.read_timeout = @config.read_timeout
      c.solr.open_timeout = @config.open_timeout
      c.solr.proxy = @config.proxy
      Session.new(c)
    end

    def connection
      session.connection
    end

    #
    # Return all collections. Refreshing every @refresh_every (default: 30.min)
    # Array:: collections
    def collections(force: false)
      collections = with_cache('LIST', force: force, key: 'CACHE_SOLR_COLLECTIONS') do |resp|
        resp['collections']
      end

      raise 'error retrieving list of collection from solr' unless collections.is_a?(Array)
      collections
    end

    #
    # Return all collections. Refreshing every @refresh_every (default: 30.min)
    # Array:: collections
    def live_nodes(force: false)
      list_nodes = with_cache('CLUSTERSTATUS', force: true, key: 'CACHE_SOLR_LIVE_NODES') do |resp|
        resp['cluster']['live_nodes'].map do |node|
          host_port = node.split(':')
          if host_port.size == 2
            port = host_port.last.gsub('_solr', '')
            "#{host_port.first}:#{port}"
          else
            node
          end
        end
      end

      return [] unless list_nodes.is_a?(Array)
      list_nodes
    end

    #
    # Return { status:, time: sec}.
    # https://lucene.apache.org/solr/guide/6_6/collections-api.html
    #
    def create_collection(collection_name:)
      collection_conf = @config.collection
      config_name = collection_conf['config_name']
      params = {}
      params[:action] = 'CREATE'
      params[:name] = collection_name
      params[:config_name] = config_name unless config_name.empty?
      CREATE_COLLECTION_MAP.each do |k, v|
        ks = k.to_s
        params[v] = collection_conf[ks] unless collection_conf[ks].nil?
      end
      begin
        response = connection.get :collections, params: params
        collections(force: true)
        return { status: 200, time: response['responseHeader']['QTime'] }
      rescue RSolr::Error::Http => e
        return { status: e.response[:status], message: e.message[/^.*$/] }
      end
    end

    #
    # Return { status: , time: sec }.
    # https://lucene.apache.org/solr/guide/6_6/collections-api.html
    #
    def delete_collection(collection_name:)
      params = {}
      params[:action] = 'DELETE'
      params[:name] = collection_name
      begin
        response = connection.get :collections, params: params
        collections(force: true)
        return { status: 200, time: response['responseHeader']['QTime'] }
      rescue RSolr::Error::Http => e
        return { status: e.response[:status], message: e.message[/^.*$/] }
      end
    end

    #
    # Return { status:, time: sec}.
    # https://lucene.apache.org/solr/guide/6_6/collections-api.html
    #
    def reload_collection(collection_name:)
      params = {}
      params[:action] = 'RELOAD'
      params[:name] = collection_name
      begin
        response = connection.get :collections, params: params
        collections(force: true)
        return { status: 200, time: response['responseHeader']['QTime'] }
      rescue RSolr::Error::Http => e
        return { status: e.response[:status], message: e.message[/^.*$/] }
      end
    end

    ### CLUSTER MAINTENANCE ###

    def clusterstatus(as_json: false)
      # don't cache it
      status = retrieve_info_solr('CLUSTERSTATUS')
      if as_json
        status.to_json
      else
        status
      end
    end

    def report_clusterstatus(view: :table)
      rows = check_cluster

      case view
      when :table
        # order first by STATUS then by COLLECTION (name)
        rows.sort! do |a, b|
          if a[:status] == :bad
            -1
          else
            a[:collection] <=> b[:collection]
          end
        end

        table = Terminal::Table.new(
          headings: [
            'Collection',
            'Replica Factor',
            'Shards',
            'Shard Active',
            'Shard Down',
            'Shard Good',
            'Shard Bad',
            'Replica UP',
            'Replica DOWN',
            'Status',
            'Recoverable'
          ],
          rows: rows.map do |row|
            [
              row[:collection],
              row[:num_replicas],
              row[:num_shards],
              row[:shard_active],
              row[:shard_non_active],
              row[:shard_good],
              row[:shard_bad],
              row[:replicas_up],
              row[:replicas_down],
              row[:status] == :ok && row[:replicas_up].positive? ? 'OK' : 'BAD',
              row[:recoverable] == :yes ? 'YES' : 'NO'
            ]
          end
        )
        puts table
      when :json
        status = rows.each_with_object({}) do |row, acc|
          name = row[:collection]
          row.delete(:collection)
          acc[name] = row
        end
        status.to_json
      when :simple
        status = 'green'
        bad_collections = []

        rows.each do |row|
          if row[:status] == :bad && row[:recoverable] == :no
            status = 'red'
            bad_collections << {
              collection: row[:collection],
              base_url: row[:bad_urls],
              recoverable: false
            }
          elsif row[:status] == :bad && row[:recoverable] == :yes
            status = 'orange' unless status == 'red'
            bad_collections << {
              collection: row[:collection],
              base_url: row[:bad_urls],
              recoverable: true
            }
          elsif row[:bad_urls].count > 0
            bad_collections << {
              collection: row[:collection],
              base_url: row[:bad_urls],
              recoverable: true
            }
          end
        end
        { status: status, bad_collections: bad_collections }.to_json
      end
    end

    def repair_collection
      replicas_not_active.each do |rep|
        delete_failed_replica(collection: rep[:collection], shard: rep[:shard], replica: rep[:replica])
        add_failed_replica(collection: rep[:collection], shard: rep[:shard], node: rep[:node])
      end
    end

    private

    def check_cluster
      replicas_not_active.clear
      cluster = clusterstatus
      analyze_collections(cluster['cluster']['collections'])
    end

    def analyze_collections(collections)
      rows = []
      collections.each_pair do |collection_name, cs|
        replica_factor = cs['replicationFactor'].to_i
        shards = cs['shards']
        shard_status = get_shard_status(collection_name, shards)
        s_active = shard_status[:active]
        s_bad = shard_status[:bad]
        status = s_active.zero? || s_bad > 0 ? :bad : :ok
        recoverable = s_active > 0 && s_bad.zero? ? :yes : :no

        rows << {
          collection: collection_name,
          num_replicas: replica_factor,
          num_shards: shards.count,
          shard_active: shard_status[:active],
          shard_non_active: shard_status[:non_active],
          shard_good: shard_status[:good],
          shard_bad: shard_status[:bad],
          replicas_up: shard_status[:replica_up],
          replicas_down: shard_status[:replica_down],
          status: status,
          recoverable: recoverable,
          bad_urls: @bad_urls[collection_name]
        }
      end

      rows
    end

    def get_shard_status(collection_name, shards)
      shards.each_with_object(
        active: 0,
        non_active: 0,
        good: 0,
        bad: 0,
        replica_up: 0,
        replica_down: 0
      ) do |(shard_name, v), acc|
        if v['state'] == 'active'
          acc[:active] += 1
        else
          acc[:non_active] += 1
        end

        replica_status = get_replicas_status(collection_name, shard_name, v['replicas'])
        acc[:replica_up] += replica_status[:active]
        acc[:replica_down] += replica_status[:non_active]

        if replica_status[:active] > 0
          acc[:good] += 1
        else
          acc[:bad] += 1
        end
      end
    end

    def get_replicas_status(collection_name, shard_name, replicas)
      @bad_urls = Hash.new { |hash, key| hash[key] = [] }

      replicas.each_with_object(
        active: 0, non_active: 0
      ) do |(core_name, v), memo|
        if v['state'] == 'active'
          memo[:active] += 1
        else
          memo[:non_active] += 1
          @bad_urls[collection_name] << v['base_url']
          @replicas_not_active << {
            collection: collection_name,
            shard: shard_name,
            replica: core_name,
            node: v['node_name'],
            base_url: v['base_url']
          }
        end
      end
    end

    # Helper function for SOLR recovery
    def delete_failed_replica(collection:, shard:, replica:)
      uri = URI(@base_url + "/admin/collections?action=DELETEREPLICA&collection=#{collection}&shard=#{shard}&replica=#{replica}")
      puts "DELETE REPLICA #{uri}"
    end

    def add_failed_replica(collection:, shard:, node:)
      uri = URI(@base_url + "/admin/collections?action=ADDREPLICA&collection=#{collection}&shard=#{shard}&node=#{node}")
      puts "ADD REPLICA #{uri}"
    end

    # Helper function for solr caching
    def with_cache(action, force: false, key: "#{CACHE_SOLR}_#{action}")
      if defined?(::Rails.cache)
        rails_cache(key, force) do
          yield(retrieve_info_solr(action))
        end
      else
        simple_cache(key, force) do
          yield(retrieve_info_solr(action))
        end
      end
    end

    def rails_cache(key, force)
      ::Rails.cache.delete(key) if force
      ::Rails.cache.fetch(key, expires_in: @refresh_every) { yield }
    rescue
      ::Rails.cache.delete(key)
      simple_cache(key, force) { yield }
    end

    def simple_cache(key, force)
      if force || (Time.now - @initialized_at) > @refresh_every
        @initialized_at = Time.now
        @cached    ||= {}
        @cached[key] = nil
      end
      @cached      ||= {}
      @cached[key] ||= yield
    end

    def retrieve_info_solr(action)
      retries = 0
      max_retries = 3
      begin
        connection.get(:collections, params: { action: action, wt: 'json' })
      rescue StandardError => e
        if retries < max_retries
          retries += 1
          sleep_for = 2**retries
          sleep(sleep_for)
          retry
        else
          raise e
        end
      end
    end
  end
end
