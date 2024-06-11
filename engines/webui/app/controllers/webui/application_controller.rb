module Webui
  class ApplicationController < ActionController::Base

    def current_page
      [params[:page].to_i, 1].max
    end

    def per_page
      [params[:per_page].to_i, 10].max
    end

    def offset_page
      (current_page - 1) * per_page
    end

    def total_pages(n_items)
      (n_items.to_f / per_page).ceil
    end

    def pages_pagination_array(total_pages)
      all_pages = total_pages.times.map(&:next)
      before_current = all_pages[[0, current_page-4].max..[0, current_page-1].max]
      after_current = all_pages[current_page..current_page+3]
      before_current + after_current
    end
  end
end
