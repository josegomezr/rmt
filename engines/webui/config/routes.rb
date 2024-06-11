Webui::Engine.routes.draw do
	root to: 'home#index'
	get '/products', to: 'products#index'
	get '/repositories', to: 'repositories#index'
	get '/subscriptions', to: 'subscriptions#index'
	get '/systems', to: 'systems#index'
end
