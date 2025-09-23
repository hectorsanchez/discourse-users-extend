# name: discourse-users-extend
# about: Plugin para mostrar usuarios de Discourse y agruparlos por país.
# version: 0.1
# authors: Héctor Sanchez

after_initialize do
  # Controlador simple sin Engine
  class ::DiscourseUsersController < ::ApplicationController
    skip_before_action :check_xhr, only: [:index, :users]
    skip_before_action :redirect_to_login_if_required, only: [:index, :users]
    
    def index
      # Página principal - renderizar HTML directamente
      render html: '<div id="main-outlet-wrapper"></div>'.html_safe, layout: 'application'
    end
    
    def users
      response.headers['Content-Type'] = 'application/json'
      response.headers['Access-Control-Allow-Origin'] = '*'
      
      api_key = SiteSetting.dmu_discourse_api_key
      api_username = SiteSetting.dmu_discourse_api_username
      discourse_url = SiteSetting.dmu_discourse_api_url
      
      if api_key.blank? || discourse_url.blank?
        render json: { error: "API Key and Discourse URL not configured properly." }, status: 400
        return
      end

      begin
        # Obtener lista de usuarios del directorio
        # El endpoint directory_items.json no acepta el parámetro 'limit'
        # Usamos los parámetros estándar: order, period, asc
        directory_url = "#{discourse_url}/directory_items.json?order=created&period=all&asc=true"
        
        directory_response = make_api_request(directory_url, api_key, api_username)
        
        if directory_response[:status_code] == 200
          directory_data = JSON.parse(directory_response[:body])
          users = directory_data['directory_items'].map { |item| item['user'] }
          
          # Process users
          processed_users = []
          users.each do |user|
            begin
              # Get complete user profile
              user_url = "#{discourse_url}/users/#{user['username']}.json"
              user_response = make_api_request(user_url, api_key, api_username)
              
              if user_response[:status_code] == 200
                user_data = JSON.parse(user_response[:body])['user']
                location = user_data['location'] || ""
                
                # Extract country
                country = "No country"
                if location.present?
                  if location.include?(',')
                    country = location.split(',').last.strip
                  else
                    country = location.strip
                  end
                end
                
                # Split name safely
                name_parts = (user_data['name'] || "").split(' ')
                firstname = name_parts.first || user_data['username']
                lastname = name_parts.drop(1).join(' ') || ""
                
                processed_user = {
                  firstname: firstname,
                  lastname: lastname,
                  email: user_data['email'],
                  username: user_data['username'],
                  location: location,
                  country: country,
                  trust_level: user_data['trust_level'],
                  avatar_template: user_data['avatar_template']
                }
                
                processed_users << processed_user
              else
                # Fallback with basic data
                processed_user = {
                  firstname: user['username'],
                  lastname: "",
                  email: nil,
                  username: user['username'],
                  location: nil,
                  country: "No country",
                  trust_level: user['trust_level'],
                  avatar_template: user['avatar_template']
                }
                processed_users << processed_user
              end
            rescue => e
              # In case of error, use basic data
              processed_user = {
                firstname: user['username'],
                lastname: "",
                email: nil,
                username: user['username'],
                location: nil,
                country: "No country",
                trust_level: user['trust_level'],
                avatar_template: user['avatar_template']
              }
              processed_users << processed_user
            end
          end
          
          # Group by country
          grouped = processed_users.group_by { |u| u[:country] }

          render json: grouped
        else
          render json: { error: "Failed to get directory", response: directory_response }
        end
      rescue => e
        render json: { error: "Error: #{e.message}" }
      end
    end

    def save_settings
      return render json: { error: "Unauthorized" }, status: 401 unless current_user&.admin?
      
      SiteSetting.dmu_discourse_api_key = params[:dmu_discourse_api_key]
      SiteSetting.dmu_discourse_api_username = params[:dmu_discourse_api_username]
      SiteSetting.dmu_discourse_api_url = params[:dmu_discourse_api_url]
      SiteSetting.dmu_discourse_api_limit = params[:dmu_discourse_api_limit]
      render json: { success: true }
    end
    
    private
    
    def make_api_request(url, api_key, api_username)
      require 'net/http'
      require 'uri'
      require 'json'
      
      uri = URI(url)
      request_uri = URI(uri.to_s)
      http = Net::HTTP.new(request_uri.host, request_uri.port)
      http.use_ssl = true if request_uri.scheme == 'https'
      http.read_timeout = 30
      
      request = Net::HTTP::Get.new(request_uri)
      request['Api-Key'] = api_key
      request['Api-Username'] = api_username
      
      response_http = http.request(request)
      
      {
        status_code: response_http.code.to_i,
        headers: response_http.to_hash,
        body: response_http.body
      }
    end
  end

  # Registrar las rutas
  Discourse::Application.routes.append do
    get '/discourse/users' => 'discourse_users#index'
    get '/discourse/users/api' => 'discourse_users#users'
    post '/discourse/save_settings' => 'discourse_users#save_settings'
  end
end