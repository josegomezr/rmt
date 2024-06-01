module Webui
  class HomeController < ApplicationController
    def index
      @products_stats = Product.group(:product_type).count.symbolize_keys
      @products_stats[:total] = @products_stats.values.sum

      @repositories_stats = {
        total: Repository.count,
        only_mirroring_enabled: Repository.only_mirroring_enabled.count,
        only_fully_mirrored: Repository.only_fully_mirrored.count,
        only_enabled: Repository.only_enabled.count,
        only_custom: Repository.only_custom.count,
        only_scc: Repository.only_scc.count,
      }

      @subscriptions_count = Subscription.count
      @systems_count = System.count
    end
  end
end
