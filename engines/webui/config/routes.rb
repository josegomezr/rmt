Webui::Engine.routes.draw do
	root to: 'home#index'
	get '/products', to: 'products#index'
end
