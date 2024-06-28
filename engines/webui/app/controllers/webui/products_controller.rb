module Webui
  class ProductsController < ApplicationController
    def index
      @products_query = Product.all
      @max_pages = total_pages(@products_query.count)
      @pages = pages_pagination_array(@max_pages)
      @products = @products_query.order(product_type: :asc, name: :asc, version: :desc, arch: :asc)
        .limit(per_page)
        .offset(offset_page)
    end
  end
end
