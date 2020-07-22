require File.expand_path('../spec_helper', File.dirname(__FILE__))

context 'indexing' do

  describe 'without sunspot_disable_ancestors' do
    it 'should index non-multivalued field with newlines' do
      expect do
        Sunspot.index!(Post.new(title: "A\nTitle"))
      end.not_to raise_error
    end

    it 'should correctly remove by model instance' do
      post = Post.new(title: 'test post')
      Sunspot.index!(post)
      Sunspot.remove!(post)
      expect(Sunspot.search(Post) { with(:title, 'test post') }.results).to be_empty
    end

    it 'should correctly delete by ID' do
      post = Post.new(title: 'test post')
      Sunspot.index!(post)
      Sunspot.remove_by_id!(Post, post.id)
      expect(Sunspot.search(Post) { with(:title, 'test post') }.results).to be_empty
    end

    it 'removes documents by query' do
      Sunspot.remove_all!
      posts = [Post.new(title: 'birds'), Post.new(title: 'monkeys')]
      Sunspot.index!(posts)

      Sunspot.remove!(Post) do
        with(:title, 'birds')
      end
      expect(Sunspot.search(Post).results.size).to eq(1)
    end

    describe 'in batches' do
      let(:post_1) { Post.new title: 'A tittle' }
      let(:post_2) { Post.new title: 'Another title' }

      describe 'nested' do
        let(:a_nested_batch) do
          Sunspot.batch do
            Sunspot.index post_1

            Sunspot.batch do
              Sunspot.index post_2
            end
          end
        end

        it 'does not fail' do
          expect { a_nested_batch }.to_not raise_error
        end
      end
    end
  end

  describe 'with sunspot_disable_ancestors' do
    it 'should index non-multivalued field with newlines' do
      expect do
        Sunspot.index!(PostWithDisableAncestors.new(title: "A\nTitle"))
      end.not_to raise_error
    end

    it 'should correctly remove by model instance' do
      post = PostWithDisableAncestors.new(title: 'test post')
      Sunspot.index!(post)
      Sunspot.remove!(post)
      expect(Sunspot.search(PostWithDisableAncestors) { with(:title, 'test post') }.results).to be_empty
    end

    it 'should correctly delete by ID' do
      post = PostWithDisableAncestors.new(title: 'test post')
      Sunspot.index!(post)
      Sunspot.remove_by_id!(PostWithDisableAncestors, post.id)
      expect(Sunspot.search(PostWithDisableAncestors) { with(:title, 'test post') }.results).to be_empty
    end

    it 'removes documents by query' do
      Sunspot.remove_all!
      posts = [PostWithDisableAncestors.new(title: 'birds'), PostWithDisableAncestors.new(title: 'monkeys')]
      Sunspot.index!(posts)

      Sunspot.remove!(PostWithDisableAncestors) do
        with(:title, 'birds')
      end
      expect(Sunspot.search(PostWithDisableAncestors).results.size).to eq(1)
    end

    describe 'in batches' do
      let(:post_1) { PostWithDisableAncestors.new title: 'A tittle' }
      let(:post_2) { PostWithDisableAncestors.new title: 'Another title' }

      describe 'nested' do
        let(:a_nested_batch) do
          Sunspot.batch do
            Sunspot.index post_1

            Sunspot.batch do
              Sunspot.index post_2
            end
          end
        end

        it 'does not fail' do
          expect { a_nested_batch }.to_not raise_error
        end
      end
    end
  end
end
