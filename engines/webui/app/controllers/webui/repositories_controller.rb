module Webui
  class RepositoriesController < ApplicationController
    def index
      @repositories_query = Repository.all
      @max_pages = total_pages(@repositories_query.count)
      @pages = pages_pagination_array(@max_pages)
      @repositories = @repositories_query
        .order(name: :asc)
        .limit(per_page)
        .offset(offset_page)
    end
  end
end
