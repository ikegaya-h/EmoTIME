Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  get '/emotime.herokuapp.com/callback', to: 'user#callback'
end
