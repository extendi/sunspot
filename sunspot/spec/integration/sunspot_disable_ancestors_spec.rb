require File.expand_path('../spec_helper', File.dirname(__FILE__))

describe 'sunspot_disable_ancestors' do
  before :each do
    Sunspot.remove_all
    @posts = PostWithDisableAncestors.new(ratings_average: 4.0, author_name: 'caio', blog_id: 1),
             PhotoPostWithDisableAncestors.new(ratings_average: 4.0, author_name: 'caio', blog_id: 1),
             VideoPost.new(ratings_average: 4.0, author_name: 'caio', blog_id: 1)
    Sunspot.index!(@posts)
  end

  it 'PostWithDisableAncestors returns returns an array with only its class name' do
    res = Sunspot.search(PostWithDisableAncestors).send(:solr_response)
    expect(res["docs"][0]["type"]).to eq(["PostWithDisableAncestors"])
    expect(res["docs"][1]["type"]).to eq(["VideoPost", "PostWithDisableAncestors", "SuperClass", "MockRecord"])
    expect(res["numFound"]).to eq(2)
  end

  it 'PhotoPostWithDisableAncestors returns an array with only its class name' do
    res = Sunspot.search(PhotoPostWithDisableAncestors).send(:solr_response)
    expect(res["docs"][0]["type"]).to eq(["PhotoPostWithDisableAncestors"])
    expect(res["numFound"]).to eq(1)
  end

  it 'VideoPost returns an array with only its class name' do
    res = Sunspot.search(VideoPost).send(:solr_response)
    expect(res["docs"][0]["type"]).to eq(["VideoPost", "PostWithDisableAncestors", "SuperClass", "MockRecord"])
    expect(res["numFound"]).to eq(1)
  end
end

describe 'without sunspot_disable_ancestors' do
  before :each do
    Sunspot.remove_all
    @posts = Post.new(ratings_average: 4.0, author_name: 'caio', blog_id: 1),
             PhotoPost.new(ratings_average: 4.0, author_name: 'caio', blog_id: 1)
    Sunspot.index!(@posts)
  end

  it 'Post returns Posts and ancestors' do
    expect(Sunspot.search(Post).send(:solr_response)["docs"][0]["type"]).to eq( ["Post", "SuperClass", "MockRecord"])
  end

  it 'PhotoPost returns PhotoPost and ancestors' do
    expect(Sunspot.search(Post).send(:solr_response)["docs"][1]["type"]).to eq(["PhotoPost", "Post", "SuperClass", "MockRecord"])
  end
end
