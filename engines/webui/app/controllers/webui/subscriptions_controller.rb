module Webui
  class SubscriptionsController < ApplicationController
    def index
      @subscriptions = Subscription.all.order(name: :asc)
      @show_regcode = params[:show_regcode].presence
    end
  end
end
