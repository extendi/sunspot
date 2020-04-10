# frozen_string_literal: true

require File.expand_path('spec_helper', File.dirname(__FILE__))
require File.expand_path('../lib/sunspot/rails/spec_helper', File.dirname(__FILE__))

class TbcPostWrong < Post
end

class TbcPostWrongTime < Post
  def collection_postfix
    'hr'
  end

  def time_routed_on
    DateTime.new(2009, 10, 1, 12, 30, 0)
  end
end

describe Sunspot::SessionProxy::TbcSessionProxy, type: :cloud do
  before :all do
    @config = Sunspot::Configuration.build
    @base_name = @config.collection['base_name']
    @old_session ||= Sunspot.session
  end

  before :each do
    @proxy = Sunspot::SessionProxy::TbcSessionProxy.new(
      date_from: Time.new(2009, 1, 1, 12),
      date_to: Time.new(2010, 1, 1, 12),
      fn_collection_filter: lambda do |collections|
        collections.select { |c| c.end_with?('_hr', '_rt') }
      end
    )
    Sunspot.session = @proxy
  end

  after :each do
    sleep 5
  end

  after :all do
    Sunspot.session = @old_session
  end

  it 'simple indexing on wrong object' do
    expect {
      @proxy.index(TbcPostWrong.new(title: 'basic post'))
    }.to raise_error NoMethodError

    expect {
      @proxy.index(TbcPostWrongTime.new(title: 'basic post'))
    }.to raise_error TypeError
  end

  it 'simple indexing on good object' do
    @proxy.index!(Post.create(title: 'basic post'))
  end

  it 'collections should contains the current one' do
    @proxy.solr.create_collection(collection_name: "#{@base_name}_2009_10_hr")

    post = Post.create(title: 'basic post', created_at: Time.new(2009, 10, 1, 12))
    ts = post.time_routed_on
    @proxy.index!(post)

    sleep 3
    c_name = @proxy.send(:collection_name, year: ts.year, month: ts.month)
    ts_start = ts - 1.month
    ts_end = ts + 1.month
    collections = @proxy.send(
      :calculate_search_collections,
      date_from: ts_start,
      date_to: ts_end
    )
    expect(collections).to include("#{c_name}_#{post.collection_postfix}")
  end

  it 'has some live nodes' do
    assert @proxy.solr.live_nodes.length > 0
  end

  it 'has some collections' do
    assert @proxy.solr.collections.length > 0
  end

  it 'retrieve only selected collection' do
    @proxy.solr.create_collection(collection_name: "#{@base_name}_2009_1")
    @proxy.solr.create_collection(collection_name: "#{@base_name}_2009_10")
    @proxy.solr.create_collection(collection_name: "#{@base_name}_2009_100")
    sleep 5

    my_proxy = Sunspot::SessionProxy::TbcSessionProxy.new(
      date_from: Time.new(2009, 1, 1, 12),
      date_to: Time.new(2010, 1, 1, 12),
      fn_collection_filter: lambda do |_collections|
        ["#{@base_name}_2009_10"]
      end
    )
    assert my_proxy.search_collections == ["#{@base_name}_2009_10"]
  end

  it 'retrieve all collections in the range' do
    @proxy.solr.create_collection(collection_name: "#{@base_name}_2018_10_a")
    @proxy.solr.create_collection(collection_name: "#{@base_name}_2018_10_b")
    @proxy.solr.create_collection(collection_name: "#{@base_name}_2018_10_c")
    sleep 5

    my_proxy = Sunspot::SessionProxy::TbcSessionProxy.new(
      date_from: Time.new(2018, 10, 1, 12),
      date_to: Time.new(2018, 10, 1, 12)
    )
    assert my_proxy.search_collections.sort == [
      "#{@base_name}_2018_10_a",
      "#{@base_name}_2018_10_b",
      "#{@base_name}_2018_10_c"
    ]
  end

  it 'retrieve only specified solr_collection' do
    @proxy.solr.create_collection(collection_name: 'test1')
    @proxy.solr.create_collection(collection_name: 'test2')
    sleep 5

    my_proxy = Sunspot::SessionProxy::TbcSessionProxy.new(
      solr_collections: ['test1', 'foo']
    )
    assert my_proxy.search_collections == ['test1']
  end

  it 'check valid collection for Post' do
    @proxy.solr.create_collection(collection_name: "#{@base_name}_2009_10_a")
    @proxy.solr.create_collection(collection_name: "#{@base_name}_2009_10_b")
    @proxy.solr.create_collection(collection_name: "#{@base_name}_2009_10_c")
    sleep 3

    post = Post.create(
      title: 'basic post',
      created_at: Time.new(2009, 10, 1, 12)
    )
    @proxy.index!(post)

    sleep 5
    supported = @proxy.calculate_valid_collections(Post)

    expect(supported).to include("#{@base_name}_2009_10_hr")
    expect(supported).not_to include(
      "#{@base_name}_2009_10_a",
      "#{@base_name}_2009_10_b",
      "#{@base_name}_2009_10_c"
    )
  end

  it 'check valid collection for Post when daily is true' do
    Sunspot::SessionProxy::TbcSessionProxy.new(
      date_from: Time.new(2009, 1, 1, 12),
      date_to: Time.new(2010, 1, 1, 12),
      daily: true
    )
    @proxy.solr.create_collection(collection_name: "#{@base_name}_2009_10_1")
    @proxy.solr.create_collection(collection_name: "#{@base_name}_2009_10_a")
    sleep 3

    post = Post.create(
      title: 'basic post',
      created_at: Time.new(2009, 10, 1, 12)
    )
    @proxy.index!(post)

    sleep 5
    supported = @proxy.calculate_valid_collections(Post)
    expect(supported).to include("#{@base_name}_2009_10_1")
    expect(supported).not_to include("#{@base_name}_2009_10_a")
  end



  it 'index two documents and retrieve one in hr type collection' do
    @proxy.solr.delete_collection(collection_name: "#{@base_name}_2009_10_hr")
    @proxy.solr.delete_collection(collection_name: "#{@base_name}_2009_10_rt")
    sleep 7

    post_a = Post.create(
      title: 'basic post on Historic',
      created_at: Time.new(2009, 10, 1, 12)
    )
    post_b = Post.create(
      title: 'basic post on Realtime',
      created_at: Time.new(2009, 10, 1, 12)
    )
    post_b.collection_postfix = 'rt'

    @proxy.index!([post_a, post_b])

    sleep 3
    collections = @proxy.send(
      :calculate_search_collections,
      date_from: Time.new(2009, 8),
      date_to: Time.new(2010, 1)
    )

    expect(collections).to include(
      "#{@base_name}_2009_10_hr",
      "#{@base_name}_2009_10_rt"
    )
  end

  it 'index some documents and search for one i a particular collection' do
    # destroy dest collections
    @proxy.solr.delete_collection(collection_name: "#{@base_name}_2009_8_hr")
    @proxy.solr.delete_collection(collection_name: "#{@base_name}_2009_8_rt")

    # create fake collections
    @proxy.solr.create_collection(collection_name: "#{@base_name}_2009_8_a")
    @proxy.solr.create_collection(collection_name: "#{@base_name}_2009_8_b")
    @proxy.solr.create_collection(collection_name: "#{@base_name}_2009_8_c")

    (1..10).each do |index|
      post = Post.create(
        body: "basic post on Historic #{index}",
        created_at: Time.new(2009, 8, 1, 12)
      )
      @proxy.index(post)
    end

    sleep 3
    post = Post.create(body: 'rt simple doc', created_at: Time.new(2009, 8, 1, 12))
    post.collection_postfix = 'rt'
    @proxy.index!(post)
    @proxy.commit

    sleep 3
    posts_hr = @proxy.search(Post) { fulltext 'basic post' }
    posts_rt = @proxy.search(Post) { fulltext 'rt simple' }

    expect(posts_hr.hits.size).to eq(10)
    expect(posts_rt.hits.size).to eq(1)
  end

  it 'creates some documents and retrieves it using Post.search method' do
    # create fake collections
    @proxy.solr.create_collection(collection_name: "#{@base_name}_2009_8_a")
    @proxy.solr.create_collection(collection_name: "#{@base_name}_2018_8_rt")
    @proxy.solr.create_collection(collection_name: "#{@base_name}_2015_8_hr")

    # creation phase
    (1..10).each do |index|
      post = Post.create(
        body: "basic post on Historic #{index}",
        created_at: Time.new(2009, 8, 1, 12)
      )
      @proxy.index(post)
    end
    @proxy.commit

    sleep 3
    # retrieving phase
    posts = Post.search { fulltext 'basic' }
    expect(posts.hits.size).to be >= 10
  end

  it "ask to search on collections that doesn't exits" do
    @proxy.solr.create_collection(collection_name: "#{@base_name}_2018_8_hr")
    sleep 5

    (1..10).each do |index|
      post = Post.create(
        body: "basic post on Historic #{index}",
        created_at: Time.new(2009, 8, 1, 12)
      )
      @proxy.index(post)
    end
    @proxy.commit
    sleep 3

    # reset proxy
    @proxy = Sunspot::SessionProxy::TbcSessionProxy.new(
      date_from: Time.new(2009, 1, 1, 12),
      date_to: Time.new(2010, 1, 1, 12),
      fn_collection_filter: lambda do |_collections|
        ['fake_collection']
      end
    )
    posts = @proxy.search(Post) { fulltext 'basic' }
    expect(posts.hits.size).to be == 0
  end

  it 'all sessions for this configuration' do
    project_sessions = @proxy.solr.collections.select { |c| c.start_with?(@base_name) }
    expect(@proxy.all_sessions.size).to eq(project_sessions.size)
  end

  describe 'remove' do
    before :each do
      @proxy = Sunspot::SessionProxy::TbcSessionProxy.new(
        date_from: Time.new(2009, 1, 1, 12),
        date_to: Time.new(2010, 1, 1, 12),
        fn_collection_filter: lambda do |collections|
          collections.select { |c| c.end_with?('_hr', '_rt') }
        end
      )
      Sunspot.session = @proxy

      # create fake collections
      @proxy.solr.create_collection(collection_name: "#{@base_name}_2009_8_hr")
      @proxy.solr.create_collection(collection_name: "#{@base_name}_2009_8_a")

      # creation phase
      (1..10).each do |index|
        post = Post.create(
          body: "basic post on Historic #{index}",
          created_at: Time.new(2009, 8, 1, 12)
        )
        @proxy.index(post)
      end
      @proxy.commit

      sleep 5
    end

    it 'remove_by_id' do
      ndocs = Post.count
      expect(Post.search.total).to eq(ndocs)
      @proxy.remove_by_id(Post, "#{@base_name}_2009_8_hr", Post.first.id)
      @proxy.commit
      sleep 3
      expect(Post.search.total).to eq(ndocs - 1)
    end

    it 'remove_by_id!' do
      ndocs = Post.count
      expect(Post.search.total).to eq(ndocs)
      @proxy.remove_by_id!(Post, "#{@base_name}_2009_8_hr", Post.first.id)
      sleep 3
      expect(Post.search.total).to eq(ndocs - 1)
    end

    it 'remove_all documents' do
      expect(Post.search.total).to eq(Post.count)
      @proxy.remove_all(Post)
      @proxy.commit
      expect(Post.search.total).to eq(0)
    end

    it 'remove_all! documents' do
      @proxy.remove_all!(Post)
      expect(Post.search.total).to eq(0)
    end
  end
end
