Discourse::Application.routes.append do
  get '/discourse-users' => 'discourse_users#index'
  get '/discourse/users' => 'discourse_users#users'
  get '/discourse/debug' => 'discourse_users#debug'
  get '/discourse/test' => 'discourse_users#test'
  post '/discourse/save_settings' => 'discourse_users#save_settings'
end
