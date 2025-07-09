Telemetry::Engine.routes.draw do
	get '/*path', to: 'tracks#package', constraints: lambda { |request| request.headers["x-track"].present? }
end
