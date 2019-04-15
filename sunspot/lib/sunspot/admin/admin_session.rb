# frozen_string_literal: true

require 'logger'
require 'terminal-table'
require 'pstore'
require 'json'

require_relative 'utils'
require_relative 'cluster_status'
require_relative 'collection_status'

module Sunspot
  module Admin
    #
    # Admin::Session connect direclty to the admin Solr endpoint
    # to handle admin stuff like collections listing, creation, etc...
    #
    class Session < Sunspot::Session
      include Sunspot::Admin::Cluster
      include Sunspot::Admin::Collection

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

      def initialize(config:, refresh_every: 600)
        @refresh_every = refresh_every
        @config = config
        @replicas_not_active = []
      end

      #
      # Return the appropriate admin session
      def session
        c = Sunspot::Configuration.build
        host_port = @config.hostnames[rand(@config.hostnames.count)].split(':')
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
        Sunspot::Session.new(c)
      end

      def connection
        session.connection
      end

      #
      # Add an host to the configure hostname
      #
      def add_hostname(host)
        @config.hostnames << host
      end

      #
      # Return all collections. Refreshing every @refresh_every (10.min)
      # Array:: collections
      def collections(force: false)
        cs = Utils.with_cache(force: force, key: 'CACHE_SOLR_COLLECTIONS', default: []) do
          resp = Utils.solr_request(connection, 'LIST')
          return [] if resp.nil?

          r = resp['collections']
          !r.is_a?(Array) || r.count.zero? ? [] : r
        end

        adjsut_solr_resp(cs)
      end

      #
      # Return all live nodes.
      # Array:: live_nodes
      def live_nodes(force: false)
        lnodes = Utils.with_cache(force: force, key: 'CACHE_SOLR_LIVE_NODES', default: []) do
          resp = Utils.solr_request(connection, 'CLUSTERSTATUS')
          r = resp['cluster']
          return [] if r.nil?

          r = r['live_nodes'].map do |node|
            host_port = node.split(':')
            if host_port.size == 2
              port = host_port.last.gsub('_solr', '')
              "#{host_port.first}:#{port}"
            else
              node
            end
          end
          r.nil? || !r.is_a?(Array) || r.count.zero? ? [] : r
        end

        adjsut_solr_resp(lnodes)
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
          status = e.try(:response).try(:[], :status)
          message = e.try(:message) || e.inspect
          return { status: status, message: (status ? message[/^.*$/] : message) }
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
          status = e.try(:response).try(:[], :status)
          message = e.try(:message) || e.inspect
          return { status: status, message: (status ? message[/^.*$/] : message) }
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
          status = e.try(:response).try(:[], :status)
          message = e.try(:message) || e.inspect
          return { status: status, message: (status ? message[/^.*$/] : message) }
        end
      end

      ############################## PRIVATE ###################################

      private

      def adjsut_solr_resp(resp)
        if resp.is_a?(String) && Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.4')
          Marshal.load(resp)
        else
          resp
        end
      end
    end
  end
end
