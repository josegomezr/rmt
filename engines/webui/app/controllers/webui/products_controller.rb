module Webui
  class ProductsController < ApplicationController
    def index
      @products = Product.all.order(product_type: :asc, name: :asc, version: :desc, arch: :asc)
    end
  end
end
