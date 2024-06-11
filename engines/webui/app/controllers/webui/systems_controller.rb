module Webui
  class SystemsController < ApplicationController
    def index
      @systems = System.all.order(login: :asc)
    end
  end
end
