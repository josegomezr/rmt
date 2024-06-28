module Webui
  class SubscriptionsController < ApplicationController
    def index
      @show_regcode = params[:show_regcode].presence

      @subscriptions_query = Subscription.all
      @max_pages = total_pages(@subscriptions_query.count)
      @pages = pages_pagination_array(@max_pages)
      @subscriptions = @subscriptions_query.order(name: :asc)
        .limit(per_page)
        .offset(offset_page)
    end
  end
end
