%w(spellcheckable fields scope paginatable adjustable field_query
   block_join block_join_json_faceting standard_query query_facet functional
   fulltext restriction restriction_with_near search more_like_this_query function
   group field_stats).each do |file|
  require File.join(File.dirname(__FILE__), 'dsl', file)
end
