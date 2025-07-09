Rails.application.routes.draw do
  mount Telemetry::Engine => "/telemetry"
end
