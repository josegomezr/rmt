module Telemetry
  class TracksController < ApplicationController
    def package
      response.headers['x-accel-redirect'] = '/files/'+request.path
      head :ok
    end
  end
end
